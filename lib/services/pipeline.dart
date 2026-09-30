import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/pack_config.dart';
import '../models/jar_info.dart';
import 'log_types.dart';
import 'process_runner.dart';
import 'proguard_service.dart';
import 'modularizer.dart';
import 'nested_jar_analyzer.dart';
import 'jpackage_service.dart';

class PipelineResult {
  final bool success;
  final String? message;
  final String? outputExePath;
  const PipelineResult({required this.success, this.message, this.outputExePath});
}

class PackPipeline {
  /// 无论 jdeps 是否检测到，都显式链入 runtime 的 JDK 模块。
  ///
  /// jdk.crypto.ec 提供 SunEC（ECDSA/ECDHE）。jlink 默认**不跟随**服务绑定
  /// （uses/provides），jdeps 也不会报告服务提供者，因此只靠依赖闭包永远拿不到它，
  /// 表现为运行期 `NoSuchAlgorithmException: EC KeyPairGenerator not available`
  /// 或对 ECDHE-only 服务端 TLS 握手失败。代价仅约 0.13MB。
  ///
  /// 切勿改用 jlink 的 `--bind-services`：实测它会把 runtime 从 6 个模块膨胀到
  /// 35+ 个（带进 jdk.compiler/jdk.javadoc/jdk.jpackage 等）。
  static const _alwaysJdkModules = ['jdk.crypto.ec'];

  final ProGuardService _proguard = ProGuardService();
  final Modularizer _modularizer = Modularizer();
  final NestedJarAnalyzer _nestedAnalyzer = NestedJarAnalyzer();
  final JPackageService _jpackage = JPackageService();

  ProcessHandle? _activeHandle;
  bool _canceled = false;

  void cancel() {
    _canceled = true;
    _activeHandle?.cancel();
  }

  Future<PipelineResult> run({
    required PackConfig config,
    required JarInfo jarInfo,
    required LogSink log,
  }) async {
    _canceled = false;

    final workDir = await _prepareWorkDir();
    log('====== 开始打包流程 ======', LogLevel.info);
    log('临时工作目录: $workDir', LogLevel.info);

    try {
      // 在临时目录中操作 jar 副本：模块化会往 jar 里写入 module-info.class，
      // 非模块化回退也要在 jar 旁边建 input 目录，直接使用原文件会改写用户的 jar、污染其所在目录。
      final workJar = p.join(workDir, p.basename(config.jarPath));
      try {
        await File(config.jarPath).copy(workJar);
      } catch (e) {
        return PipelineResult(success: false, message: '复制 jar 到临时目录失败（文件被占用？）: $e');
      }
      return await _runPipeline(
        config: config,
        jarInfo: jarInfo,
        workDir: workDir,
        activeJar: workJar,
        log: log,
      );
    } finally {
      // 任务完成后清理临时工作目录，防止 C 盘缓存堆积
      await _cleanupWorkDir(workDir, log);
    }
  }

  Future<PipelineResult> _runPipeline({
    required PackConfig config,
    required JarInfo jarInfo,
    required String workDir,
    required String activeJar,
    required LogSink log,
  }) async {
    if (_canceled) return _canceledResult();

    // JavaFX SDK 前置校验：放在混淆/模块化之前，避免白跑数分钟耗时步骤后才报错。
    // JavaFX 通过 jpackage --module-path/--add-modules 交给 jlink 链入 runtime。
    // 切勿把 JavaFX jar 放进 --input（会进 classpath，与模块路径冲突，导致 Failed to launch JVM）。
    String? fxModulePath;
    final fxAddModules = config.javafxModules.isNotEmpty
        ? config.javafxModules
        : 'javafx.controls,javafx.fxml,javafx.graphics';
    if (jarInfo.needsJavaFxSdk) {
      if (config.javafxSdkPath == null || config.javafxSdkPath!.isEmpty) {
        return const PipelineResult(
          success: false,
          message: '检测到 JavaFX 应用，但未指定 JavaFX SDK 路径。请在参数表单中填写 JavaFX SDK 路径。',
        );
      }
      final fxLibDir = p.join(config.javafxSdkPath!, 'lib');
      if (!await Directory(fxLibDir).exists()) {
        return PipelineResult(
          success: false,
          message: 'JavaFX SDK lib 目录不存在: $fxLibDir',
        );
      }
      fxModulePath = fxLibDir;
      log('检测到 JavaFX 应用，将通过 jlink 链接: $fxLibDir ($fxAddModules)', LogLevel.info);
    }

    if (config.enableProGuard) {
      log('步骤 1/4: ProGuard 混淆', LogLevel.info);
      final obfuscated = p.join(workDir, 'obfuscated.jar');
      final handle = ProcessHandle();
      _activeHandle = handle;
      final ok = await _proguard.run(
        inputJar: activeJar,
        outputJar: obfuscated,
        mainClass: config.mainClass,
        javaPath: p.join(config.jdkPath, 'bin', 'java.exe'),
        jdkPath: config.jdkPath,
        keepResources: config.keepResources,
        javafxSdkPath: jarInfo.needsJavaFxSdk ? config.javafxSdkPath : null,
        log: log,
        handle: handle,
      );
      _activeHandle = null;
      if (_canceled) return _canceledResult();
      if (!ok) {
        return const PipelineResult(success: false, message: 'ProGuard 混淆失败');
      }
      activeJar = obfuscated;
    } else {
      log('步骤 1/4: 跳过 ProGuard 混淆（已关闭）', LogLevel.info);
    }

    String moduleName = config.moduleName.isNotEmpty ? config.moduleName : jarInfo.moduleName;

    // 嵌套 jar（lib/*.jar）里的依赖 jdeps 看不见，必须先单独分析：
    // fat jar 常把依赖 jar 原样塞进 lib/，像 okhttp/okio/jfoenix 需要的 java.logging
    // 就会被完全漏掉，最终运行期 NoClassDefFoundError（java/util/logging/Logger）。
    // 放在模块化之前，这些模块还能一并写进 module-info 的 requires。
    final nestedModules = await _nestedAnalyzer.analyze(
      jarPath: activeJar,
      jdkPath: config.jdkPath,
      log: log,
    );
    if (nestedModules.isNotEmpty) {
      log('[Nested] 嵌套 jar 额外需要的模块: ${nestedModules.join(', ')}', LogLevel.info);
    }

    log('步骤 2/4: 模块化处理', LogLevel.info);
    ModularizeResult modResult;
    if (config.enableModularPackaging) {
      log('[Modular] 已启用模块化打包（class 隐藏进 jimage）。'
          '注意：命名模块下 Class.getResource 不再回退到系统类加载器，'
          '若应用用 new Image("logo/x.png") 这类非 package 路径加载资源会启动失败。',
          LogLevel.warning);
      final modHandle = ProcessHandle();
      _activeHandle = modHandle;
      modResult = await _modularizer.modularize(
        jarPath: activeJar,
        jdkPath: config.jdkPath,
        log: log,
        handle: modHandle,
        extraModulePath: fxModulePath,
        extraRequiredModules: nestedModules,
      );
      _activeHandle = null;
      if (_canceled) return _canceledResult();
    } else {
      // 默认走 classpath 打包。模块化会把应用变成 JPMS 命名模块，而 JavaFX 应用
      // 普遍把资源放在非 package 目录（logo/、fxml/）并用 Class.getResource 加载，
      // 命名模块下会直接找不到资源、启动即崩（实测确认）。因此默认关闭，
      // 改为用 jdeps + 嵌套 jar 分析把依赖模块补进 jlink，保证 runtime 完整。
      log('[Modular] 跳过模块化，使用 classpath 打包（兼容性最好）', LogLevel.info);
      modResult = await _analyzeDepsWithoutModularizing(activeJar, config.jdkPath, log);
    }

    bool useModular = modResult.success;
    if (!useModular) {
      log('[Modular] ${modResult.message ?? "模块化失败"}', LogLevel.warning);
      log('[Modular] 将回退到非模块化打包模式（class 不会完全隐藏，但功能可用）', LogLevel.warning);
    } else if (config.enableModularPackaging) {
      moduleName = modResult.moduleName ?? moduleName;
    }

    // 组装 jlink 的 --add-modules（依赖闭包的根）：
    //   1) JavaFX 模块——jlink 不会凭 module-info 自动找到 JavaFX SDK 里的模块；
    //   2) jdeps 实测出的应用依赖（java.logging/java.sql 等）——注意**模块化失败退回
    //      非模块化时尤其要带上**：此时 jar 是普通 jar、没有 module-info 提供依赖闭包，
    //      若还让 --add-modules 只含 JavaFX，jlink 就只链入 JavaFX 闭包，
    //      运行期必然 NoClassDefFoundError（java/util/logging/Logger 等）；
    //   3) 固定兜底的 JDK 模块（见 _alwaysJdkModules）。
    //
    // 重要：jpackage 一旦收到 --add-modules，jlink 的模块集就被限制成该列表的
    // 传递闭包，不再使用 jpackage 的默认全集。因此当**一个模块都没有**时不能传空
    // 列表——非 JavaFX 且 jdeps 无结果时保持不传，沿用 jpackage 默认模块集。
    final addModuleSet = <String>{
      if (fxModulePath != null) ...fxAddModules.split(','),
      ...modResult.requiredModules,
      ...nestedModules,
      ..._alwaysJdkModules,
    };
    final addModulesArg =
        addModuleSet.map((s) => s.trim()).where((s) => s.isNotEmpty).join(',');

    if (addModulesArg.isEmpty) {
      log('[jlink] 未指定 --add-modules，使用 jpackage 默认模块集（体积较大但兼容性最好）',
          LogLevel.info);
    } else {
      log('[jlink] --add-modules $addModulesArg', LogLevel.info);
      if (modResult.requiredModules.isEmpty) {
        log('[jlink] 提示: jdeps 未检测到 JDK 模块依赖；若应用运行时报 '
            'NoClassDefFoundError，多为反射/服务加载用法所致', LogLevel.info);
      }
    }

    // 清理旧的 app-image 目录（jpackage 不覆盖已存在的目录）
    final oldAppImageDir = p.join(config.outputDir, config.appName);
    try {
      await _cleanOldAppImage(oldAppImageDir, config.appName, log);
    } catch (e) {
      return PipelineResult(success: false, message: e.toString());
    }

    // 合并用户 java options；JavaFX 时补充 library path
    final javaOpts = <String>[];
    if (config.javaOptions.isNotEmpty) {
      javaOpts.addAll(
        config.javaOptions.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty),
      );
    }
    if (fxModulePath != null) {
      if (!javaOpts.any((o) => o.contains('java.library.path'))) {
        javaOpts.add(r'-Djava.library.path=$APPDIR');
      }
    }
    final mergedJavaOptions = javaOpts.join('\n');

    log('步骤 3/4: jpackage 生成 app-image', LogLevel.info);
    final handle = ProcessHandle();
    _activeHandle = handle;
    final JPackageResult result;
    if (useModular) {
      final modulePath = p.dirname(activeJar);
      result = await _jpackage.buildAppImage(
        jpackagePath: p.join(config.jdkPath, 'bin', 'jpackage.exe'),
        appName: config.appName,
        appVersion: config.appVersion,
        moduleName: moduleName,
        mainClass: config.mainClass,
        modulePath: modulePath,
        outputDir: config.outputDir,
        vendor: config.vendor,
        iconPath: config.iconPath,
        javaOptions: mergedJavaOptions,
        appArguments: config.appArguments,
        extraModulePath: fxModulePath,
        addModules: addModulesArg.isEmpty ? null : addModulesArg,
        log: log,
        handle: handle,
      );
    } else {
      // 非模块化模式：仅业务 jar 进 input，用 --main-jar 引用
      // （activeJar 位于临时 workDir，input 目录随 workDir 一并清理）
      final inputDir = p.join(p.dirname(activeJar), 'input');
      await Directory(inputDir).create(recursive: true);
      final inputJarPath = p.join(inputDir, p.basename(activeJar));
      await File(activeJar).copy(inputJarPath);

      result = await _jpackage.buildAppImageNonModular(
        jpackagePath: p.join(config.jdkPath, 'bin', 'jpackage.exe'),
        appName: config.appName,
        appVersion: config.appVersion,
        mainJar: inputJarPath,
        mainClass: config.mainClass,
        inputDir: inputDir,
        outputDir: config.outputDir,
        vendor: config.vendor,
        iconPath: config.iconPath,
        javaOptions: mergedJavaOptions,
        appArguments: config.appArguments,
        modulePath: fxModulePath,
        addModules: addModulesArg.isEmpty ? null : addModulesArg,
        log: log,
        handle: handle,
      );
    }
    _activeHandle = null;
    if (_canceled) return _canceledResult();
    if (!result.success) {
      return PipelineResult(success: false, message: result.message);
    }

    final appImageDir = p.join(config.outputDir, config.appName);
    final exePath = p.join(appImageDir, '${config.appName}.exe');

    // jlink 只链入 JavaFX 模块 class，不会自动带上 SDK bin 下的 native DLL。
    // 把 DLL 拷到 app/（$APPDIR），并确保 cfg 中有 java.library.path。
    if (jarInfo.needsJavaFxSdk &&
        config.javafxSdkPath != null &&
        config.javafxSdkPath!.isNotEmpty) {
      await _copyJavaFxNatives(
        javafxSdkPath: config.javafxSdkPath!,
        appImageDir: appImageDir,
        appName: config.appName,
        addModules: fxAddModules,
        stripUnused: config.stripUnusedJavaFxDlls,
        log: log,
      );
    }

    if (config.generateMsi) {
      log('步骤 4/4: jpackage 生成 msi 安装包', LogLevel.info);
      final msiHandle = ProcessHandle();
      _activeHandle = msiHandle;
      final msiResult = await _jpackage.buildMsi(
        jpackagePath: p.join(config.jdkPath, 'bin', 'jpackage.exe'),
        appName: config.appName,
        appVersion: config.appVersion,
        appImageDir: appImageDir,
        outputDir: config.outputDir,
        vendor: config.vendor,
        log: log,
        handle: msiHandle,
      );
      _activeHandle = null;
      if (_canceled) return _canceledResult();
      if (!msiResult.success) {
        log('msi 生成失败，但 app-image 已成功', LogLevel.warning);
      }
    } else {
      log('步骤 4/4: 跳过 msi 生成（未勾选）', LogLevel.info);
    }

    log('====== 打包完成 ======', LogLevel.success);
    log('可执行文件: $exePath', LogLevel.success);
    return PipelineResult(success: true, outputExePath: exePath);
  }

  /// classpath 模式下只需依赖分析结果（不需要 module-info）：
  /// 复用 Modularizer 的 `jdeps --list-deps` 兜底分析，拿到应用依赖的模块，
  /// 供后续并入 jlink 的 `--add-modules`，避免 runtime 缺模块。
  ///
  /// 返回的 ModularizeResult.success 恒为 false —— 语义是「不走模块化」，
  /// 调用方据此选择 classpath 打包分支。
  Future<ModularizeResult> _analyzeDepsWithoutModularizing(
    String jarPath,
    String jdkPath,
    LogSink log,
  ) async {
    final modules = await _modularizer.listDependencyModules(
      jarPath: jarPath,
      jdkPath: jdkPath,
      log: log,
    );
    return ModularizeResult(
      success: false,
      message: '已按配置跳过模块化（classpath 打包）',
      requiredModules: modules,
    );
  }

  Future<String> _prepareWorkDir() async {
    final tmp = await getTemporaryDirectory();
    final workDir = p.join(
      tmp.path,
      'jpackage_gui_build_${DateTime.now().millisecondsSinceEpoch}',
    );
    await Directory(workDir).create(recursive: true);
    return workDir;
  }

  Future<void> _cleanupWorkDir(String workDir, LogSink log) async {
    try {
      final dir = Directory(workDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        log('已清理临时工作目录: $workDir', LogLevel.info);
      }
    } catch (e) {
      log('清理临时目录失败（不影响打包结果）: $e', LogLevel.warning);
    }
  }

  Future<void> _cleanOldAppImage(String dirPath, String appName, LogSink log) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    log('清理旧的输出目录: $dirPath', LogLevel.info);

    final exeName = '$appName.exe';
    try {
      final result = await Process.run(
        'taskkill',
        ['/IM', exeName, '/F', '/T'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        log('已终止正在运行的 $exeName 进程', LogLevel.info);
        await Future.delayed(const Duration(milliseconds: 800));
      }
    } catch (_) {}

    for (int i = 0; i < 3; i++) {
      try {
        await dir.delete(recursive: true);
        return;
      } catch (e) {
        if (i < 2) {
          log('删除旧目录失败，等待后重试... (${i + 1}/3): $e', LogLevel.warning);
          await Future.delayed(const Duration(seconds: 1));
        } else {
          log('无法删除旧目录: $e', LogLevel.error);
          log('请手动关闭正在运行的 $exeName，或删除 $dirPath 后重试', LogLevel.error);
          throw Exception('无法清理旧目录，可能 $exeName 正在运行或文件被锁定');
        }
      }
    }
  }

  Future<void> _copyJavaFxNatives({
    required String javafxSdkPath,
    required String appImageDir,
    required String appName,
    required String addModules,
    required bool stripUnused,
    required LogSink log,
  }) async {
    final fxBinDir = Directory(p.join(javafxSdkPath, 'bin'));
    if (!await fxBinDir.exists()) {
      log('JavaFX SDK bin 目录不存在，跳过 native DLL 复制: ${fxBinDir.path}', LogLevel.warning);
      return;
    }

    // 只放进 app/（$APPDIR），不要堆到 exe 同级目录，保持根目录干净
    final appDir = Directory(p.join(appImageDir, 'app'));
    await appDir.create(recursive: true);

    // 根据 addModules 决定哪些 native DLL 需要复制（仅在 stripUnused 开启时裁剪）
    // javafx.web → jfxwebkit.dll（~93MB）
    // javafx.media → gstreamer-lite.dll, jfxmedia.dll, fxplugins.dll
    // javafx.graphics → glass.dll, prism_*.dll, javafx_font.dll, decora_sse.dll, javafx_iio.dll（必需）
    final Set<String> excludedDlls;
    if (stripUnused) {
      final modules = addModules.toLowerCase();
      final hasWeb = modules.contains('javafx.web');
      final hasMedia = modules.contains('javafx.media');
      excludedDlls = {
        if (!hasWeb) 'jfxwebkit.dll',
        if (!hasMedia) ...{
          'gstreamer-lite.dll',
          'jfxmedia.dll',
          'fxplugins.dll',
        },
      };
    } else {
      excludedDlls = {};
    }

    int count = 0;
    await for (final entity in fxBinDir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.endsWith('.dll')) continue;
      if (excludedDlls.contains(name)) {
        continue;
      }
      await entity.copy(p.join(appDir.path, p.basename(entity.path)));
      count++;
    }
    final savedMsg = excludedDlls.isNotEmpty
        ? '（已排除 ${excludedDlls.length} 个未使用模块的 DLL: ${excludedDlls.join(", ")}）'
        : '';
    log('已复制 $count 个 JavaFX native DLL 到 app/ $savedMsg', LogLevel.info);

    // 确保 cfg 有 java.library.path=$APPDIR
    final cfgPath = p.join(appImageDir, 'app', '$appName.cfg');
    final cfgFile = File(cfgPath);
    if (await cfgFile.exists()) {
      var content = await cfgFile.readAsString();
      if (!content.contains('java.library.path')) {
        if (!content.contains('[JavaOptions]')) {
          content = '${content.trimRight()}\n\n[JavaOptions]\n';
        }
        content = '${content.trimRight()}\njava-options=-Djava.library.path=\$APPDIR\n';
        await cfgFile.writeAsString(content);
        log('已写入 java.library.path=\$APPDIR 到 $cfgPath', LogLevel.info);
      }
    }
  }

  PipelineResult _canceledResult() {
    return const PipelineResult(success: false, message: '用户已取消');
  }
}

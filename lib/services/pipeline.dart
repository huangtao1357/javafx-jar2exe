import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/pack_config.dart';
import '../models/jar_info.dart';
import 'log_types.dart';
import 'proguard_service.dart';
import 'modularizer.dart';
import 'jpackage_service.dart';

class PipelineResult {
  final bool success;
  final String? message;
  final String? outputExePath;
  const PipelineResult({required this.success, this.message, this.outputExePath});
}

class PackPipeline {
  final ProGuardService _proguard = ProGuardService();
  final Modularizer _modularizer = Modularizer();
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

    final originalJar = config.jarPath;
    String activeJar = originalJar;

    if (_canceled) return _canceledResult();

    if (config.enableProGuard) {
      log('步骤 1/4: ProGuard 混淆', LogLevel.info);
      final obfuscated = p.join(workDir, 'obfuscated.jar');
      final ok = await _proguard.run(
        inputJar: activeJar,
        outputJar: obfuscated,
        mainClass: config.mainClass,
        javaPath: p.join(config.jdkPath, 'bin', 'java.exe'),
        jdkPath: config.jdkPath,
        keepResources: config.keepResources,
        javafxSdkPath: jarInfo.needsJavaFxSdk ? config.javafxSdkPath : null,
        log: log,
      );
      if (!ok) {
        return const PipelineResult(success: false, message: 'ProGuard 混淆失败');
      }
      activeJar = obfuscated;
    } else {
      log('步骤 1/4: 跳过 ProGuard 混淆（已关闭）', LogLevel.info);
    }

    if (_canceled) return _canceledResult();

    String moduleName = config.moduleName.isNotEmpty ? config.moduleName : jarInfo.moduleName;
    log('步骤 2/4: 模块化处理', LogLevel.info);
    final modResult = await _modularizer.modularize(
      jarPath: activeJar,
      jdkPath: config.jdkPath,
      log: log,
    );
    bool useModular = modResult.success;
    if (!useModular) {
      log('[Modular] ${modResult.message ?? "模块化失败"}', LogLevel.warning);
      log('[Modular] 将回退到非模块化打包模式（class 不会完全隐藏，但功能可用）', LogLevel.warning);
    } else {
      moduleName = modResult.moduleName ?? moduleName;
    }

    if (_canceled) return _canceledResult();

    // 清理旧的 app-image 目录（jpackage 不覆盖已存在的目录）
    final oldAppImageDir = p.join(config.outputDir, config.appName);
    try {
      await _cleanOldAppImage(oldAppImageDir, config.appName, log);
    } catch (e) {
      return PipelineResult(success: false, message: e.toString());
    }

    // JavaFX：通过 jpackage --module-path/--add-modules 交给 jlink 链入 runtime。
    // 切勿把 JavaFX jar 放进 --input（会进 classpath，与模块路径冲突，导致 Failed to launch JVM）。
    String? fxModulePath;
    const fxAddModules = 'javafx.controls,javafx.fxml,javafx.graphics';
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
        addModules: fxModulePath != null ? fxAddModules : null,
        log: log,
        handle: handle,
      );
    } else {
      // 非模块化模式：仅业务 jar 进 input，用 --main-jar 引用
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
        addModules: fxModulePath != null ? fxAddModules : null,
        log: log,
        handle: handle,
      );
    }
    _activeHandle = null;
    if (!result.success) {
      return PipelineResult(success: false, message: result.message);
    }

    if (_canceled) return _canceledResult();

    final appImageDir = p.join(config.outputDir, config.appName);
    final exePath = p.join(appImageDir, '${config.appName}.exe');

    // jlink 只链入 JavaFX 模块 class，不会自动带上 SDK bin 下的 native DLL。
    // 把 DLL 拷到 app 根与 runtime/bin，并确保 cfg 中有 java.library.path。
    if (jarInfo.needsJavaFxSdk &&
        config.javafxSdkPath != null &&
        config.javafxSdkPath!.isNotEmpty) {
      await _copyJavaFxNatives(
        javafxSdkPath: config.javafxSdkPath!,
        appImageDir: appImageDir,
        appName: config.appName,
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

  Future<String> _prepareWorkDir() async {
    final tmp = await getTemporaryDirectory();
    final workDir = p.join(
      tmp.path,
      'jpackage_gui_build_${DateTime.now().millisecondsSinceEpoch}',
    );
    await Directory(workDir).create(recursive: true);
    return workDir;
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
    required LogSink log,
  }) async {
    final fxBinDir = Directory(p.join(javafxSdkPath, 'bin'));
    if (!await fxBinDir.exists()) {
      log('JavaFX SDK bin 目录不存在，跳过 native DLL 复制: ${fxBinDir.path}', LogLevel.warning);
      return;
    }

    // 只放进 app/（$APPDIR），不要堆到 exe 同级目录，保持根目录干净：
    //   AppName.exe
    //   app/
    //   runtime/
    final appDir = Directory(p.join(appImageDir, 'app'));
    await appDir.create(recursive: true);

    int count = 0;
    await for (final entity in fxBinDir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.endsWith('.dll')) continue;
      // 跳过会与 runtime 自带 CRT 冲突/重复的通用运行库（可选保留也可）
      await entity.copy(p.join(appDir.path, p.basename(entity.path)));
      count++;
    }
    log('已复制 $count 个 JavaFX native DLL 到 app/（不污染 exe 同级目录）', LogLevel.info);

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

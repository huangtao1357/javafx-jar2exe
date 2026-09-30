import 'dart:convert';
import 'dart:io';import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'log_types.dart';
import 'process_runner.dart';

class ModularizeResult {
  final bool success;
  final String? moduleName;
  final String? message;

  /// jdeps 生成的 module-info 中声明的 JDK/第三方模块（`requires` 列表）。
  /// 这些模块必须同时进入 jlink 的 `--add-modules`，否则 runtime 里没有它们，
  /// 应用运行时抛 NoClassDefFoundError（如 java.util.logging.Logger 缺失）。
  final List<String> requiredModules;

  const ModularizeResult({
    required this.success,
    this.moduleName,
    this.message,
    this.requiredModules = const [],
  });
}

class Modularizer {
  Future<ModularizeResult> modularize({
    required String jarPath,
    required String jdkPath,
    required LogSink log,
    ProcessHandle? handle,
    String? extraModulePath,
    Set<String> extraRequiredModules = const {},
  }) async {
    final bin = p.join(jdkPath, 'bin');
    final jdeps = p.join(bin, 'jdeps.exe');
    final javac = p.join(bin, 'javac.exe');
    final jar = p.join(bin, 'jar.exe');

    if (!File(jdeps).existsSync() || !File(javac).existsSync() || !File(jar).existsSync()) {
      return ModularizeResult(
        success: false,
        message: 'JDK bin 中未找到 jdeps/javac/jar（路径: $bin）',
      );
    }

    final tmp = await getTemporaryDirectory();
    final workDir = p.join(
      tmp.path,
      'jpackage_gui_mod_${DateTime.now().millisecondsSinceEpoch}',
    );
    await Directory(workDir).create(recursive: true);

    try {
      log('[Modular] 检查 jar 是否已模块化', LogLevel.info);
      final alreadyModule = await _describeModule(jar, jarPath);
      if (alreadyModule.success) {
        log('[Modular] jar 已是模块化 jar，模块名: ${alreadyModule.moduleName}', LogLevel.success);
        return alreadyModule;
      }

      // JavaFX SDK 必须进 --module-path：否则 jdeps 无法解析 javafx.* 引用，
      // 生成的 module-info 会丢失 requires javafx.*，jlink 只链入 --add-modules 显式
      // 列出的模块，最终 runtime 残缺、运行期抛 NoClassDefFoundError/IllegalAccessError。
      // --ignore-missing-deps：fat jar 常含未打包进 jar 的可选依赖（如 okhttp 的可选
      // 平台类），缺少它会让整个 module-info 生成失败并回退到非模块化打包。
      final jdepsArgs = <String>['--generate-module-info', workDir];
      if (extraModulePath != null && extraModulePath.isNotEmpty) {
        jdepsArgs.addAll(['--module-path', extraModulePath]);
      }
      jdepsArgs.addAll(['--ignore-missing-deps', jarPath]);

      log('[Modular] jdeps ${jdepsArgs.join(' ')}', LogLevel.command);
      final jdepsResult = await runProcess(jdeps, jdepsArgs,
          log: log, tag: '[Modular]', handle: handle);
      if (!jdepsResult) {
        // module-info 生成失败（典型：fat jar 带失效的 META-INF/services，
        // 导致无法派生自动模块描述符）不代表依赖无从得知：
        // `jdeps --list-deps` 走 class 分析路径，不做模块描述符校验，仍能列出依赖。
        // 必须尽量拿到它——回退到非模块化后，这些模块是唯一能进入 jlink 的途径，
        // 漏掉就是运行期 NoClassDefFoundError。
        final fallback = await _listDepsModules(jdeps, jarPath, extraModulePath, log, handle);
        return ModularizeResult(
          success: false,
          message: 'jdeps 生成 module-info 失败',
          requiredModules: fallback,
        );
      }

      final moduleInfoFile = await _findModuleInfo(workDir);
      if (moduleInfoFile == null) {
        return ModularizeResult(
          success: false,
          message: '未找到生成的 module-info.java',
        );
      }

      // jdeps 生成的 module-info 可能带 `provides X with Y`，而 X 所属模块并不存在：
      // 一旦用了 --ignore-missing-deps，jdeps 会照写 provides 却丢掉对应的 requires，
      // javac 随即报「程序包 X 不存在」。典型来源是 fat jar 里只打包了半个可选集成
      // （如 fastjson 的 javax.ws.rs.ext / org.glassfish.jersey.internal.spi）。
      // 服务绑定不是打包必需项，直接剔除 provides 才能让模块化流程走完。
      final content = await File(moduleInfoFile).readAsString();
      final sanitized = _stripProvides(content);
      await File(moduleInfoFile).writeAsString(sanitized.content);

      final moduleInfoContent = sanitized.content;
      final moduleName = _parseModuleName(moduleInfoContent);
      if (moduleName == null) {
        return ModularizeResult(success: false, message: '无法解析 module-info.java 中的模块名');
      }

      if (sanitized.droppedProvides.isNotEmpty) {
        log('[Modular] 已剔除 ${sanitized.droppedProvides.length} 条无法解析的 provides 声明'
            '（不影响功能，避免 javac 因缺失可选依赖而失败）', LogLevel.warning);
      }

      // jdeps 推断出的依赖模块，需要并入 jlink 的 --add-modules
      final requiredModules = _parseRequiredModules(moduleInfoContent);

      // 嵌套 jar 的依赖 jdeps 看不到，注入到 module-info 的 requires，
      // 否则 app 模块读不到这些模块，运行期抛 IllegalAccessError
      // （"module X does not read module java.logging"）。
      final injected = extraRequiredModules
          .where((m) => !requiredModules.contains(m) && m != 'java.base')
          .toList();
      if (injected.isNotEmpty) {
        final patched = _injectRequires(moduleInfoFile, injected);
        await File(moduleInfoFile).writeAsString(patched);
        requiredModules.addAll(injected);
        log('[Modular] 注入嵌套 jar 依赖到 module-info: ${injected.join(', ')}',
            LogLevel.info);
      }

      if (requiredModules.isNotEmpty) {
        log('[Modular] 依赖模块合计: ${requiredModules.join(', ')}', LogLevel.info);
      }

      // javac 编译 module-info 时同样必须带 --module-path：module-info 里的
      // `requires javafx.*` 需要 JavaFX SDK 才能解析，否则报「找不到模块: javafx.base」
      // 并使整个模块化流程失败、退回非模块化（class 明文暴露）。
      final javacArgs = <String>[
        if (extraModulePath != null && extraModulePath.isNotEmpty) ...[
          '--module-path', extraModulePath,
        ],
        '--patch-module', '$moduleName=$jarPath',
        '-d', workDir,
        moduleInfoFile,
      ];
      log('[Modular] javac ${javacArgs.join(' ')}', LogLevel.command);
      final javacOk = await runProcess(javac, javacArgs,
          log: log, tag: '[Modular]', handle: handle);
      if (!javacOk) {
        return ModularizeResult(success: false, message: 'javac 编译 module-info 失败');
      }

      final moduleClass = p.join(workDir, 'module-info.class');
      if (!File(moduleClass).existsSync()) {
        return ModularizeResult(success: false, message: 'module-info.class 未生成');
      }

      log('[Modular] jar --update --file="$jarPath" --module-version=1.0 -C $workDir module-info.class', LogLevel.command);
      final jarOk = await runProcess(jar, [
        '--update',
        '--file=$jarPath',
        '--module-version=1.0',
        '-C', workDir,
        'module-info.class',
      ], log: log, tag: '[Modular]', handle: handle);
      if (!jarOk) {
        return ModularizeResult(success: false, message: 'jar 更新 module-info.class 失败');
      }

      log('[Modular] 模块化完成，模块名: $moduleName', LogLevel.success);
      return ModularizeResult(
        success: true,
        moduleName: moduleName,
        requiredModules: requiredModules,
      );
    } finally {
      try {
        await Directory(workDir).delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 只做依赖分析（`jdeps --list-deps`），不生成 module-info。
  /// 供 classpath 打包模式使用：此时不需要模块描述符，但仍必须知道应用依赖哪些
  /// JDK 模块，否则 `--add-modules` 凑不齐、runtime 缺模块导致运行期崩溃。
  Future<List<String>> listDependencyModules({
    required String jarPath,
    required String jdkPath,
    required LogSink log,
    String? extraModulePath,
  }) async {
    final jdeps = p.join(jdkPath, 'bin', 'jdeps.exe');
    if (!File(jdeps).existsSync()) {
      log('[Modular] 未找到 jdeps，跳过依赖分析（将使用 jpackage 默认模块集）',
          LogLevel.warning);
      return [];
    }
    return _listDepsModules(jdeps, jarPath, extraModulePath, log, null);
  }

  /// `jdeps --list-deps` 兜底：module-info 生成失败时仍列出应用依赖的模块。
  /// 该模式只做 class 级分析，不校验模块描述符，因此对带失效 service 的 fat jar 有效。
  Future<List<String>> _listDepsModules(
    String jdeps,
    String jarPath,
    String? extraModulePath,
    LogSink log,
    ProcessHandle? handle,
  ) async {
    final args = <String>['--list-deps'];
    if (extraModulePath != null && extraModulePath.isNotEmpty) {
      args.addAll(['--module-path', extraModulePath]);
    }
    args.addAll(['--ignore-missing-deps', jarPath]);

    log('[Modular] 回退分析: jdeps ${args.join(' ')}', LogLevel.command);
    try {
      final result = await Process.run(
        jdeps,
        args,
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      ).timeout(const Duration(seconds: 60));
      final modules = <String>{};
      for (final raw in const LineSplitter().convert(result.stdout as String)) {
        final t = raw.trim();
        if (t.isEmpty || t == 'java.base') continue;
        if (!RegExp(r'^[A-Za-z_][\w.]*$').hasMatch(t)) continue;
        modules.add(t);
      }
      if (modules.isNotEmpty) {
        log('[Modular] 回退分析得到依赖模块: ${modules.join(', ')}', LogLevel.info);
      } else {
        log('[Modular] 回退分析未得到可用模块列表', LogLevel.warning);
      }
      return modules.toList();
    } catch (e) {
      log('[Modular] 回退分析失败: $e', LogLevel.warning);
      return [];
    }
  }

  /// 通过 `jar --describe-module` 判断 jar 是否为显式模块化 jar，并提取模块名。
  /// 模块化 jar 首行形如 `<module>[@<version>] jar:file:...!/module-info.class`；
  /// 非模块化 jar 输出的是本地化提示文案（如“找不到模块描述符”），不含该标记，
  /// 因此不能靠匹配 "Module" 关键词判断（旧实现因此永远识别不出模块化 jar）。
  Future<ModularizeResult> _describeModule(String jarExe, String jarPath) async {
    try {
      final result = await Process.run(
        jarExe,
        ['--describe-module', '--file=$jarPath'],
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      );
      if (result.exitCode != 0) {
        return const ModularizeResult(success: false);
      }
      final out = result.stdout as String;
      final firstLine = out.isEmpty ? '' : out.split('\n').first.trim();
      if (!firstLine.contains('/module-info.class')) {
        return const ModularizeResult(success: false);
      }
      final token = firstLine.split(RegExp(r'\s+')).first;
      // 模块名本身不含 '@'，'@' 之后是版本号
      final at = token.indexOf('@');
      final name = at > 0 ? token.substring(0, at) : token;
      if (name.isEmpty) {
        return const ModularizeResult(success: false);
      }
      return ModularizeResult(success: true, moduleName: name);
    } catch (e) {
      return ModularizeResult(success: false, message: e.toString());
    }
  }

  Future<String?> _findModuleInfo(String dir) async {
    final entries = await Directory(dir).list(recursive: true).toList();
    for (final e in entries) {
      if (e is File && e.path.endsWith('module-info.java')) return e.path;
    }
    return null;
  }

  String? _parseModuleName(String content) {
    final m = RegExp(r'module\s+(\S+)\s*\{').firstMatch(content);
    return m?.group(1);
  }

  /// 把 `requires <mod>;` 注入到 module-info.java 的模块声明之后。
  /// 插入到 `{` 紧跟的行后面，位置对语法无影响。
  String _injectRequires(String moduleInfoPath, List<String> modules) {
    final lines = File(moduleInfoPath).readAsLinesSync();
    final headerIdx = lines.indexWhere((l) => l.trim().startsWith('module '));
    if (headerIdx < 0) return lines.join('\n');
    final out = <String>[...lines];
    out.insertAll(
      headerIdx + 1,
      modules.map((m) => '    requires $m;'),
    );
    return out.join('\n');
  }

  /// 剔除 module-info 中所有的 `provides ... with ...;` 声明。
  /// `provides` 只影响 JPMS 服务绑定（jlink --bind-services），打包不依赖它；
  /// 而它引用的服务接口所属模块常常不在 jar 里，会让 javac 直接编译失败。
  ({String content, List<String> droppedProvides}) _stripProvides(String content) {
    final out = <String>[];
    final dropped = <String>[];
    bool skipping = false;
    for (final line in const LineSplitter().convert(content)) {
      final t = line.trim();
      if (skipping) {
        // provides 可能跨多行，直到分号结束
        if (t.endsWith(';')) skipping = false;
        continue;
      }
      if (t.startsWith('provides ')) {
        dropped.add(t.split(RegExp(r'\s+'))[1]);
        // 单行 provides 自身以 ';' 结尾；否则进入续行模式
        if (!t.endsWith(';')) skipping = true;
        continue;
      }
      out.add(line);
    }
    return (content: out.join('\n'), droppedProvides: dropped);
  }

  /// 从 module-info.java 提取顶层 `requires` 的模块名。
  /// 只取匹配行开头的 requires（顶层缩进 4 空格），因此 `requires transitive x` 也能命中，
  /// 而 `requires static` 位于同一行属于安全冗余（加入 --add-modules 无副作用）。
  /// java.base 恒为隐式依赖，jlink 也禁止显式传入，故排除。
  List<String> _parseRequiredModules(String content) {
    final re = RegExp(
      r'^\s*requires\s+(?:transitive\s+|static\s+)*([A-Za-z_][\w.]*)',
      multiLine: true,
    );
    final seen = <String>{};
    for (final m in re.allMatches(content)) {
      final name = m.group(1)!;
      if (name != 'java.base') seen.add(name);
    }
    return seen.toList();
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
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
        return ModularizeResult(
          success: false,
          message: 'jdeps 生成 module-info 失败',
        );
      }

      final moduleInfoFile = await _findModuleInfo(workDir);
      if (moduleInfoFile == null) {
        return ModularizeResult(
          success: false,
          message: '未找到生成的 module-info.java',
        );
      }

      final moduleInfoContent = await File(moduleInfoFile).readAsString();
      final moduleName = _parseModuleName(moduleInfoContent);
      if (moduleName == null) {
        return ModularizeResult(success: false, message: '无法解析 module-info.java 中的模块名');
      }

      // jdeps 推断出的依赖模块，需要并入 jlink 的 --add-modules
      final requiredModules = _parseRequiredModules(moduleInfoContent);
      if (requiredModules.isNotEmpty) {
        log('[Modular] jdeps 检测到依赖模块: ${requiredModules.join(', ')}', LogLevel.info);
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

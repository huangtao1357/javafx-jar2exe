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
  const ModularizeResult({required this.success, this.moduleName, this.message});
}

class Modularizer {
  Future<ModularizeResult> modularize({
    required String jarPath,
    required String jdkPath,
    required LogSink log,
    ProcessHandle? handle,
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

      log('[Modular] jdeps --generate-module-info $workDir "$jarPath"', LogLevel.command);
      final jdepsResult = await runProcess(jdeps, [
        '--generate-module-info',
        workDir,
        jarPath,
      ], log: log, tag: '[Modular]', handle: handle);
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

      final moduleName = _parseModuleName(await File(moduleInfoFile).readAsString());
      if (moduleName == null) {
        return ModularizeResult(success: false, message: '无法解析 module-info.java 中的模块名');
      }

      log('[Modular] javac --patch-module $moduleName=$jarPath -d $workDir module-info.java', LogLevel.command);
      final javacOk = await runProcess(javac, [
        '--patch-module', '$moduleName=$jarPath',
        '-d', workDir,
        moduleInfoFile,
      ], log: log, tag: '[Modular]', handle: handle);
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
      return ModularizeResult(success: true, moduleName: moduleName);
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
}

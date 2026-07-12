import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'log_types.dart';

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

    log('[Modular] 检查 jar 是否已模块化', LogLevel.info);
    final alreadyModule = await _isModularJar(jar, jarPath);
    if (alreadyModule.success) {
      log('[Modular] jar 已是模块化 jar，模块名: ${alreadyModule.moduleName}', LogLevel.success);
      return alreadyModule;
    }

    log('[Modular] jdeps --generate-module-info $workDir "$jarPath"', LogLevel.command);
    final jdepsResult = await _runProcess(jdeps, [
      '--generate-module-info',
      workDir,
      jarPath,
    ], log: log, tag: '[Modular]');
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
    final javacOk = await _runProcess(javac, [
      '--patch-module', '$moduleName=$jarPath',
      '-d', workDir,
      moduleInfoFile,
    ], log: log, tag: '[Modular]');
    if (!javacOk) {
      return ModularizeResult(success: false, message: 'javac 编译 module-info 失败');
    }

    final moduleClass = p.join(workDir, 'module-info.class');
    if (!File(moduleClass).existsSync()) {
      return ModularizeResult(success: false, message: 'module-info.class 未生成');
    }

    log('[Modular] jar --update --file="$jarPath" --module-version=1.0 -C $workDir module-info.class', LogLevel.command);
    final jarOk = await _runProcess(jar, [
      '--update',
      '--file=$jarPath',
      '--module-version=1.0',
      '-C', workDir,
      'module-info.class',
    ], log: log, tag: '[Modular]');
    if (!jarOk) {
      return ModularizeResult(success: false, message: 'jar 更新 module-info.class 失败');
    }

    log('[Modular] 模块化完成，模块名: $moduleName', LogLevel.success);
    return ModularizeResult(success: true, moduleName: moduleName);
  }

  Future<ModularizeResult> _isModularJar(String jarExe, String jarPath) async {
    try {
      final result = await Process.run(jarExe, ['--describe-module', '--file=$jarPath']);
      final out = result.stdout as String;
      if (result.exitCode == 0 && out.contains('Module')) {
        final m = RegExp(r'No module for .*|Module (\S+)').firstMatch(out);
        if (m != null && m.group(1) != null) {
          return ModularizeResult(success: true, moduleName: m.group(1));
        }
      }
      return const ModularizeResult(success: false);
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

  Future<bool> _runProcess(
    String executable,
    List<String> args, {
    required LogSink log,
    required String tag,
  }) async {
    try {
      final proc = await Process.start(executable, args, runInShell: false);
      final stdoutSub = proc.stdout
          .transform<String>(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) => log('$tag $line', LogLevel.info));
      final stderrSub = proc.stderr
          .transform<String>(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) => log('$tag $line', LogLevel.warning));
      final code = await proc.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();
      return code == 0;
    } catch (e) {
      log('$tag 进程异常: $e', LogLevel.error);
      return false;
    }
  }
}

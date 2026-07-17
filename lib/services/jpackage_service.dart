import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'log_types.dart';

class JPackageResult {
  final bool success;
  final String? message;
  const JPackageResult({required this.success, this.message});
}

class JPackageService {
  Future<JPackageResult> buildAppImage({
    required String jpackagePath,
    required String appName,
    required String appVersion,
    required String moduleName,
    required String mainClass,
    required String modulePath,
    required String outputDir,
    required String vendor,
    String? iconPath,
    String javaOptions = '',
    String appArguments = '',
    String? extraModulePath,
    String? addModules,
    required LogSink log,
    ProcessHandle? handle,
  }) async {
    final effectiveModulePath = (extraModulePath != null && extraModulePath.isNotEmpty)
        ? '$modulePath${Platform.pathSeparator}$extraModulePath'
        : modulePath;
    final args = <String>[
      '--type', 'app-image',
      '--name', appName,
      '--app-version', appVersion,
      '--module', '$moduleName/$mainClass',
      '--module-path', effectiveModulePath,
      '--dest', outputDir,
      '--vendor', vendor,
      '--verbose',
      // jpackage 默认已 strip-debug/no-header-files/no-man-pages，额外添加 compress=2
      '--jlink-options', '--compress=2',
    ];
    if (addModules != null && addModules.isNotEmpty) {
      args.addAll(['--add-modules', addModules]);
    }
    if (iconPath != null && iconPath.isNotEmpty) {
      args.addAll(['--icon', iconPath]);
    }
    if (javaOptions.isNotEmpty) {
      for (final opt in javaOptions.split('\n').where((s) => s.trim().isNotEmpty)) {
        args.addAll(['--java-options', opt.trim()]);
      }
    }
    if (appArguments.isNotEmpty) {
      args.addAll(['--arguments', appArguments]);
    }

    log('[jpackage] $jpackagePath ${args.join(' ')}', LogLevel.command);
    String? errorMsg;
    final ok = await _runProcess(
      jpackagePath,
      args,
      log: log,
      tag: '[jpackage]',
      handle: handle,
      onError: (msg) => errorMsg = msg,
    );
    if (!ok) {
      if (errorMsg != null && errorMsg!.contains('AccessDeniedException')) {
        return const JPackageResult(
          success: false,
          message: '文件被锁定（AccessDeniedException），可能是上一次生成的 exe 仍在运行或被杀毒软件拦截。请关闭正在运行的程序，或将输出目录添加到杀毒软件白名单后重试。',
        );
      }
      return const JPackageResult(success: false, message: 'jpackage 构建失败');
    }
    return const JPackageResult(success: true);
  }

  Future<JPackageResult> buildAppImageNonModular({
    required String jpackagePath,
    required String appName,
    required String appVersion,
    required String mainJar,
    required String mainClass,
    required String inputDir,
    required String outputDir,
    required String vendor,
    String? iconPath,
    String javaOptions = '',
    String appArguments = '',
    String? modulePath,
    String? addModules,
    required LogSink log,
    ProcessHandle? handle,
  }) async {
    final args = <String>[
      '--type', 'app-image',
      '--name', appName,
      '--app-version', appVersion,
      '--input', inputDir,
      '--main-jar', p.basename(mainJar),
      '--main-class', mainClass,
      '--dest', outputDir,
      '--vendor', vendor,
      '--verbose',
      // jpackage 默认已 strip-debug/no-header-files/no-man-pages，额外添加 compress=2
      '--jlink-options', '--compress=2',
    ];
    // JavaFX 等外部模块：交给 jlink 链进 runtime，不要放进 --input classpath
    if (modulePath != null && modulePath.isNotEmpty) {
      args.addAll(['--module-path', modulePath]);
    }
    if (addModules != null && addModules.isNotEmpty) {
      args.addAll(['--add-modules', addModules]);
    }
    if (iconPath != null && iconPath.isNotEmpty) {
      args.addAll(['--icon', iconPath]);
    }
    if (javaOptions.isNotEmpty) {
      for (final opt in javaOptions.split('\n').where((s) => s.trim().isNotEmpty)) {
        args.addAll(['--java-options', opt.trim()]);
      }
    }
    if (appArguments.isNotEmpty) {
      args.addAll(['--arguments', appArguments]);
    }

    log('[jpackage] $jpackagePath ${args.join(' ')}', LogLevel.command);
    String? errorMsg;
    final ok = await _runProcess(
      jpackagePath,
      args,
      log: log,
      tag: '[jpackage]',
      handle: handle,
      onError: (msg) => errorMsg = msg,
    );
    if (!ok) {
      if (errorMsg != null && errorMsg!.contains('AccessDeniedException')) {
        return const JPackageResult(
          success: false,
          message: '文件被锁定（AccessDeniedException），可能是上一次生成的 exe 仍在运行或被杀毒软件拦截。请关闭正在运行的程序，或将输出目录添加到杀毒软件白名单后重试。',
        );
      }
      return const JPackageResult(success: false, message: 'jpackage 非模块化构建失败');
    }
    return const JPackageResult(success: true);
  }

  Future<JPackageResult> buildMsi({
    required String jpackagePath,
    required String appName,
    required String appVersion,
    required String appImageDir,
    required String outputDir,
    required String vendor,
    required LogSink log,
    ProcessHandle? handle,
  }) async {
    final args = <String>[
      '--type', 'msi',
      '--name', appName,
      '--app-version', appVersion,
      '--app-image', appImageDir,
      '--dest', outputDir,
      '--vendor', vendor,
      '--win-per-user-install',
      '--verbose',
    ];

    log('[jpackage] $jpackagePath ${args.join(' ')}', LogLevel.command);
    final ok = await _runProcess(
      jpackagePath,
      args,
      log: log,
      tag: '[jpackage]',
      handle: handle,
    );
    if (!ok) {
      return const JPackageResult(success: false, message: 'msi 安装包生成失败');
    }
    return const JPackageResult(success: true);
  }

  Future<bool> _runProcess(
    String executable,
    List<String> args, {
    required LogSink log,
    required String tag,
    ProcessHandle? handle,
    void Function(String errorMessage)? onError,
  }) async {
    Process? proc;
    final errorLines = <String>[];
    try {
      proc = await Process.start(executable, args, runInShell: false);
      handle?.attach(proc);
      final stdoutSub = proc.stdout
          .transform<String>(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
        log('$tag $line', LogLevel.info);
        if (line.contains('AccessDeniedException') ||
            line.contains('错误:') ||
            line.contains('PackagerException')) {
          errorLines.add(line);
        }
      });
      final stderrSub = proc.stderr
          .transform<String>(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
        log('$tag $line', LogLevel.warning);
        errorLines.add(line);
      });
      final code = await proc.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();
      if (code != 0 && onError != null && errorLines.isNotEmpty) {
        onError(errorLines.join('\n'));
      }
      return code == 0;
    } catch (e) {
      log('$tag 进程异常: $e', LogLevel.error);
      return false;
    } finally {
      handle?.detach();
    }
  }
}

class ProcessHandle {
  Process? _proc;
  bool _canceled = false;
  bool get canceled => _canceled;

  void attach(Process p) {
    _proc = p;
    if (_canceled) {
      p.kill(ProcessSignal.sigkill);
    }
  }

  void detach() {
    _proc = null;
  }

  void cancel() {
    _canceled = true;
    _proc?.kill(ProcessSignal.sigkill);
  }
}

String defaultAppImageDir(String outputDir, String appName) =>
    p.join(outputDir, appName);

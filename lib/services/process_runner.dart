import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'log_types.dart';

/// 可取消的外部进程句柄。
/// cancel() 立即杀死已 attach 的进程；若在 attach 之前被取消，
/// 则记住取消状态，进程启动后第一时间补杀。
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

/// 统一的外部进程执行器：
/// - 注入 JAVA_TOOL_OPTIONS 强制子进程 UTF-8 输出，修复中文 Windows 下
///   jpackage/JDK 工具日志乱码（JDK 18 以下无 stdout.encoding 属性，会被忽略，
///   file.encoding 足以解决主要乱码）；
/// - stdout/stderr 逐行转发到日志，stderr 以 warning 级别呈现；
/// - 收集典型错误行，供调用方识别 AccessDeniedException 等失败原因。
Future<bool> runProcess(
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
    final env = Map<String, String>.from(Platform.environment);
    final existing = env['JAVA_TOOL_OPTIONS'] ?? '';
    const utf8Opts = '-Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8';
    env['JAVA_TOOL_OPTIONS'] = existing.isEmpty ? utf8Opts : '$existing $utf8Opts';
    proc = await Process.start(executable, args, runInShell: false, environment: env);
    handle?.attach(proc);
    final stdoutSub = proc.stdout
        .transform<String>(const Utf8Decoder(allowMalformed: true))
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
        .transform<String>(const Utf8Decoder(allowMalformed: true))
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

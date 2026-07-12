import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/pack_config.dart';
import '../models/jar_info.dart';
import '../services/config_storage.dart';
import '../services/jdk_detector.dart';
import '../services/jar_analyzer.dart';
import '../services/log_types.dart';
import '../services/pipeline.dart';

class LogEntry {
  final DateTime timestamp;
  final String line;
  final LogLevel level;
  const LogEntry({
    required this.timestamp,
    required this.line,
    required this.level,
  });

  String toTextLine() =>
      '[${timestamp.toIso8601String()}] ${level.name.padRight(7)} $line';
}

class PackViewModel extends ChangeNotifier {
  final ConfigStorage _storage = ConfigStorage();
  final JarAnalyzer _analyzer = JarAnalyzer();
  final PackPipeline _pipeline = PackPipeline();

  PackConfig config = PackConfig();
  JarInfo? jarInfo;
  JdkInfo? jdkInfo;

  final List<LogEntry> logEntries = [];
  bool isPacking = false;
  String? lastOutputExe;
  String? errorMessage;

  bool _autoScroll = true;
  bool get autoScroll => _autoScroll;
  void setAutoScroll(bool v) {
    _autoScroll = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _saveConfig();
    super.dispose();
  }

  Future<void> init() async {
    final loaded = await _storage.load();
    if (loaded != null) config = loaded;
    jdkInfo = await JdkDetector.detect();
    if (jdkInfo != null && config.jdkPath.isEmpty) {
      config.jdkPath = jdkInfo!.jdkPath;
    }
    if (config.outputDir.isEmpty) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      config.outputDir = p.join(exeDir, 'output');
    }
    notifyListeners();
  }

  Future<void> _saveConfig() async {
    await _storage.save(config);
  }

  Future<void> selectJar(String path) async {
    if (path.isEmpty) return;
    config.jarPath = path;
    errorMessage = null;
    notifyListeners();
    try {
      jarInfo = await _analyzer.analyze(path);
      config.applyJarInfo(jarInfo!);
      if (jarInfo!.candidateEntries.isEmpty) {
        errorMessage = '未在 jar 中找到任何入口类（含 main 方法或 JavaFX Application 子类），请手动输入 Main-Class';
      }
    } catch (e) {
      errorMessage = '解析 jar 失败: $e';
    }
    await _saveConfig();
    notifyListeners();
  }

  void updateConfig(void Function(PackConfig c) updater) {
    updater(config);
    notifyListeners();
  }

  Future<void> pickJdkPath(String? path) async {
    if (path == null || path.isEmpty) return;
    config.jdkPath = path;
    final info = JdkInfo(
      jdkPath: path,
      jpackagePath: p.join(path, 'bin', 'jpackage.exe'),
      javaPath: p.join(path, 'bin', 'java.exe'),
      javacPath: p.join(path, 'bin', 'javac.exe'),
      jdepsPath: p.join(path, 'bin', 'jdeps.exe'),
      jarPath: p.join(path, 'bin', 'jar.exe'),
    );
    jdkInfo = info;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> startPack() async {
    if (isPacking) return;
    final err = config.validate();
    if (err != null) {
      errorMessage = err;
      notifyListeners();
      return;
    }
    if (jarInfo == null) {
      try {
        jarInfo = await _analyzer.analyze(config.jarPath);
      } catch (e) {
        errorMessage = 'jar 解析失败: $e';
        notifyListeners();
        return;
      }
    }

    logEntries.clear();
    isPacking = true;
    errorMessage = null;
    lastOutputExe = null;
    notifyListeners();

    void onLog(String line, LogLevel level) {
      logEntries.add(LogEntry(
        timestamp: DateTime.now(),
        line: line,
        level: level,
      ));
      notifyListeners();
    }

    try {
      final result = await _pipeline.run(
        config: config,
        jarInfo: jarInfo!,
        log: onLog,
      );
      if (!result.success) {
        errorMessage = result.message ?? '打包失败';
      } else {
        lastOutputExe = result.outputExePath;
      }
    } catch (e, st) {
      errorMessage = '打包异常: $e';
      onLog('异常堆栈: $st', LogLevel.error);
    } finally {
      isPacking = false;
      await _saveConfig();
      await _dumpBuildLog();
      notifyListeners();
    }
  }

  void cancelPack() {
    if (!isPacking) return;
    _pipeline.cancel();
  }

  Future<void> openOutputDir() async {
    final exe = lastOutputExe;
    final target = exe != null ? p.dirname(exe) : config.outputDir;
    if (target.isEmpty) return;
    final dir = Directory(target);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    await Process.start('explorer.exe', [target], runInShell: true);
  }

  void clearLogs() {
    logEntries.clear();
    notifyListeners();
  }

  Future<void> _dumpBuildLog() async {
    try {
      final dir = Directory(config.outputDir);
      if (!dir.existsSync()) return;
      final logPath = p.join(config.outputDir, '${config.appName}-build.log');
      final sb = StringBuffer();
      for (final e in logEntries) {
        sb.writeln(e.toTextLine());
      }
      await File(logPath).writeAsString(sb.toString());
    } catch (_) {}
  }

  Future<void> saveLogToFile(String destPath) async {
    final sb = StringBuffer();
    for (final e in logEntries) {
      sb.writeln(e.toTextLine());
    }
    await File(destPath).writeAsString(sb.toString());
  }

  Future<void> resetConfig() async {
    await _storage.clear();
    config = PackConfig();
    jarInfo = null;
    lastOutputExe = null;
    errorMessage = null;
    logEntries.clear();
    if (jdkInfo != null) config.jdkPath = jdkInfo!.jdkPath;
    notifyListeners();
  }
}

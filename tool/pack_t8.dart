import 'dart:io';
import 'package:jpackage_gui/models/jar_info.dart';
import 'package:jpackage_gui/models/pack_config.dart';
import 'package:jpackage_gui/services/jar_analyzer.dart';
import 'package:jpackage_gui/services/log_types.dart';
import 'package:jpackage_gui/services/pipeline.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MockPathProvider extends PathProviderPlatform {
  final _dir = Directory(r'C:\Users\huangtao\AppData\Local\Temp\jpackage_gui_pack');

  @override
  Future<String?> getTemporaryPath() async {
    await _dir.create(recursive: true);
    return _dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    await _dir.create(recursive: true);
    return _dir.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    await _dir.create(recursive: true);
    return _dir.path;
  }
}

Future<void> main() async {
  PathProviderPlatform.instance = _MockPathProvider();
  await Directory(r'C:\Users\huangtao\AppData\Local\Temp\jpackage_gui_pack')
      .create(recursive: true);

  final jarPath = r'E:\2026\7月\7.11\T8FrigServer.jar';
  final outputDir = r'E:\2026\7月\7.11';
  final iconPath = r'E:\2026\7月\7.11\logo.ico';
  final logFile = File(r'E:\2026\7月\7.11\T8FrigServer-build.log');
  final logSink = logFile.openWrite();

  void log(String line, LogLevel level) {
    final msg = '[${DateTime.now().toIso8601String()}] ${level.name.padRight(7)} $line';
    stdout.writeln(msg);
    logSink.writeln(msg);
  }

  final analyzer = JarAnalyzer();
  final JarInfo jarInfo = await analyzer.analyze(jarPath);
  log('manifestMain: ${jarInfo.manifestMainClass}', LogLevel.info);
  log('needsJavaFx: ${jarInfo.needsJavaFxSdk}', LogLevel.info);
  for (final e in jarInfo.candidateEntries.take(10)) {
    log('  candidate: ${e.label}', LogLevel.info);
  }

  // Prefer sample.Launcher if present (user's previous pack used it)
  String mainClass = jarInfo.defaultEntry?.className ?? 'sample.Main';
  for (final e in jarInfo.candidateEntries) {
    if (e.className == 'sample.Launcher') {
      mainClass = 'sample.Launcher';
      break;
    }
  }

  final config = PackConfig(
    jarPath: jarPath,
    appName: 'T8FrigServer',
    appVersion: '1.0.0',
    mainClass: mainClass,
    outputDir: outputDir,
    vendor: '',
    jdkPath: r'D:\develop\jdk-17.0.12',
    moduleName: jarInfo.moduleName,
    enableProGuard: true,
    keepResources: true,
    generateMsi: false,
    iconPath: File(iconPath).existsSync() ? iconPath : null,
    javafxSdkPath: jarInfo.needsJavaFxSdk
        ? r'E:\jpackage-gui\test_assets\javafx-sdk-17.0.2'
        : null,
  );

  log('mainClass: $mainClass', LogLevel.info);
  log('javafxSdk: ${config.javafxSdkPath}', LogLevel.info);

  final pipeline = PackPipeline();
  final result = await pipeline.run(
    config: config,
    jarInfo: jarInfo,
    log: log,
  );

  await logSink.flush();
  await logSink.close();

  if (!result.success) {
    stderr.writeln('PACK FAILED: ${result.message}');
    exit(1);
  }
  stdout.writeln('PACK OK: ${result.outputExePath}');
  exit(0);
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpackage_gui/models/jar_info.dart';
import 'package:jpackage_gui/models/pack_config.dart';
import 'package:jpackage_gui/services/jar_analyzer.dart';
import 'package:jpackage_gui/services/log_types.dart';
import 'package:jpackage_gui/services/pipeline.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// 直接通过接口包，避免 path_provider 直接依赖

class _MockPathProvider extends PathProviderPlatform {
  final _dir = Directory(r'C:\Users\huangtao\AppData\Local\Temp\jpackage_gui_test');

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _MockPathProvider();

  test('T8FrigServer end-to-end pack', () async {
    final jarPath = r'E:\2026\7月\7.11\T8FrigServer.jar';
    if (!File(jarPath).existsSync()) {
      // ignore: avoid_print
      print('Skip: T8FrigServer.jar not present');
      return;
    }
    final outputDir = r'e:\jpackage-gui\test_assets\t8_out';
    await Directory(outputDir).create(recursive: true);
    await Directory(r'C:\Users\huangtao\AppData\Local\Temp\jpackage_gui_test')
        .create(recursive: true);

    final analyzer = JarAnalyzer();
    final JarInfo jarInfo = await analyzer.analyze(jarPath);
    // ignore: avoid_print
    print('manifestMain: ${jarInfo.manifestMainClass}');
    // ignore: avoid_print
    print('moduleName: ${jarInfo.moduleName}');
    // ignore: avoid_print
    print('candidates (${jarInfo.candidateEntries.length}):');
    for (final e in jarInfo.candidateEntries.take(5)) {
      // ignore: avoid_print
      print('  - ${e.label}');
    }
    expect(jarInfo.candidateEntries, isNotEmpty);

    final config = PackConfig(
      jarPath: jarPath,
      appName: 'T8FrigServer',
      appVersion: '1.0.0',
      mainClass: jarInfo.defaultEntry?.className ?? 'sample.Main',
      outputDir: outputDir,
      vendor: 'TestVendor',
      jdkPath: r'D:\develop\jdk-17.0.12',
      moduleName: jarInfo.moduleName,
      enableProGuard: true,
      keepResources: true,
      generateMsi: false,
      javafxSdkPath: jarInfo.needsJavaFxSdk
          ? r'e:\jpackage-gui\test_assets\javafx-sdk-17.0.2'
          : null,
    );
    config.applyJarInfo(jarInfo);
    config.mainClass = jarInfo.defaultEntry?.className ?? 'sample.Main';

    final pipeline = PackPipeline();
    final result = await pipeline.run(
      config: config,
      jarInfo: jarInfo,
      log: (String line, LogLevel level) {
        // ignore: avoid_print
        print('${level.name.padRight(7)} $line');
      },
    );

    expect(result.success, true, reason: result.message ?? '');
    expect(File(result.outputExePath!).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

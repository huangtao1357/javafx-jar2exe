import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _MockPathProvider();

  test('pack T8FrigServer to user dir', () async {
    final jarPath = r'E:\2026\7月\7.11\T8FrigServer.jar';
    final outputDir = r'E:\2026\7月\7.11';
    final iconPath = r'E:\2026\7月\7.11\logo.ico';
    expect(File(jarPath).existsSync(), isTrue);

    final analyzer = JarAnalyzer();
    final JarInfo jarInfo = await analyzer.analyze(jarPath);
    // ignore: avoid_print
    print('needsJavaFx=${jarInfo.needsJavaFxSdk} candidates=${jarInfo.candidateEntries.map((e) => e.className).join(",")}');

    String mainClass = jarInfo.manifestMainClass ??
        jarInfo.defaultEntry?.className ??
        'sample.Main';

    final config = PackConfig(
      jarPath: jarPath,
      appName: 'T8FrigServer',
      appVersion: '1.0.0',
      mainClass: mainClass,
      outputDir: outputDir,
      vendor: 'T8',
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

    final pipeline = PackPipeline();
    final result = await pipeline.run(
      config: config,
      jarInfo: jarInfo,
      log: (line, level) {
        // ignore: avoid_print
        print('${level.name.padRight(7)} $line');
      },
    );
    expect(result.success, isTrue, reason: result.message ?? '');
    expect(File(result.outputExePath!).existsSync(), isTrue);
    // ignore: avoid_print
    print('PACK_OK ${result.outputExePath}');
  }, timeout: const Timeout(Duration(minutes: 15)));
}

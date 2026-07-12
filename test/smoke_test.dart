import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpackage_gui/services/jar_analyzer.dart';
import 'package:jpackage_gui/services/jdk_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JarAnalyzer parses ConsoleApp jar', () async {
    final jarPath = r'e:\jpackage-gui\test_assets\consoleapp.jar';
    if (!File(jarPath).existsSync()) {
      // ignore: avoid_print
      print('Skip: test jar not present');
      return;
    }
    final analyzer = JarAnalyzer();
    final info = await analyzer.analyze(jarPath);
    expect(info.candidateEntries, isNotEmpty);
    expect(info.candidateEntries.any((e) => e.className == 'demo.ConsoleApp'), isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('JdkDetector finds JDK on this machine', () async {
    final info = await JdkDetector.detect();
    expect(info, isNotNull);
    expect(File(info!.jpackagePath).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpackage_gui/models/pack_config.dart';
import 'package:jpackage_gui/services/jar_analyzer.dart';
import 'package:jpackage_gui/services/jdk_detector.dart';
import 'package:jpackage_gui/services/log_types.dart';
import 'package:jpackage_gui/services/modularizer.dart';
import 'package:jpackage_gui/services/pipeline.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MockPathProvider extends PathProviderPlatform {
  late final Directory _dir;

  _MockPathProvider() {
    _dir = Directory.systemTemp.createTempSync('jpackage_gui_fix_test');
  }

  @override
  Future<String?> getTemporaryPath() async {
    _dir.createSync(recursive: true);
    return _dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async => _dir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

const _testAssets = r'E:\jpackage-gui\test_assets';
const _consoleJar = '$_testAssets\\consoleapp.jar';
// 已模块化的 jar（JavaFX SDK 内每个 jar 都带 module-info.class）
const _modularJar = '$_testAssets\\javafx-sdk-17.0.2\\lib\\javafx.base.jar';
// 内嵌 JavaFX 类的 fat jar
const _fatJar = '$_testAssets\\helloapp-fat.jar';

int _fnv1a(List<int> bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

int _countModTempDirs() {
  final tmp = Directory.systemTemp;
  if (!tmp.existsSync()) return 0;
  return tmp
      .listSync()
      .whereType<Directory>()
      .where((d) => p.basename(d.path).startsWith('jpackage_gui_mod_'))
      .length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mockPaths = _MockPathProvider();
  PathProviderPlatform.instance = mockPaths;

  test('已模块化 jar 走快速路径，返回真实模块名（不再被 jdeps 拒绝）', () async {
    if (!File(_modularJar).existsSync()) {
      markTestSkipped('modular jar not present at $_modularJar');
    }
    final jdk = await JdkDetector.detect();
    if (jdk == null) {
      markTestSkipped('JDK not detected (JAVA_HOME=${Platform.environment['JAVA_HOME']})');
      return;
    }
    final leakedBefore = _countModTempDirs();
    final result = await Modularizer().modularize(
      jarPath: _modularJar,
      jdkPath: jdk.jdkPath,
      log: (_, _) {},
    );
    expect(result.success, true, reason: result.message);
    expect(result.moduleName, 'javafx.base');
    // 快速路径不应留下临时目录
    expect(_countModTempDirs(), leakedBefore);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('fat jar 内嵌 JavaFX 类时不再误报需要 SDK', () async {
    if (!File(_fatJar).existsSync()) {
      // ignore: avoid_print
      print('Skip: fat jar not present');
      return;
    }
    final info = await JarAnalyzer().analyze(_fatJar);
    expect(info.bundlesJavaFx, true);
    expect(info.needsJavaFxSdk, false);
  });

  test('PackConfig 校验：版本号格式与应用名非法字符', () {
    final bad = PackConfig(
      jarPath: 'a.jar',
      appName: 'my app',
      appVersion: '1.0-beta',
      mainClass: 'demo.Main',
      outputDir: 'out',
      jdkPath: 'jdk',
    );
    expect(bad.validate(), contains('版本号格式无效'));

    final illegalName = bad..appName = r'my:app';
    expect(illegalName.validate(), contains('非法字符'));

    final trailingDot = PackConfig(
      jarPath: 'a.jar',
      appName: 'myapp.',
      appVersion: '1.0',
      mainClass: 'demo.Main',
      outputDir: 'out',
      jdkPath: 'jdk',
    );
    expect(trailingDot.validate(), isNotNull);

    final good = PackConfig(
      jarPath: 'a.jar',
      appName: 'my app',
      appVersion: '1.0.0',
      mainClass: 'demo.Main',
      outputDir: 'out',
      jdkPath: 'jdk',
    );
    expect(good.validate(), isNull);
  });

  test('端到端打包（ProGuard 关闭）：用户原始 jar 不被改写、目录不被污染、临时目录不泄漏', () async {
    if (!File(_consoleJar).existsSync()) {
      markTestSkipped('consoleapp.jar not present at $_consoleJar');
    }
    final jdk = await JdkDetector.detect();
    if (jdk == null) {
      markTestSkipped('JDK not detected (JAVA_HOME=${Platform.environment['JAVA_HOME']})');
      return;
    }

    final jarBefore = await File(_consoleJar).readAsBytes();
    final leakedBefore = _countModTempDirs();

    final outputDir = '$_testAssets\\review_out';
    final outDir = Directory(outputDir);
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    outDir.createSync(recursive: true);

    final analyzer = JarAnalyzer();
    final jarInfo = await analyzer.analyze(_consoleJar);
    expect(jarInfo.candidateEntries, isNotEmpty);

    final config = PackConfig(
      jarPath: _consoleJar,
      appName: 'consoleapp',
      appVersion: '1.0.0',
      mainClass: jarInfo.defaultEntry?.className ?? 'demo.ConsoleApp',
      outputDir: outputDir,
      vendor: 'TestVendor',
      jdkPath: jdk.jdkPath,
      enableProGuard: false,
      generateMsi: false,
    );

    final logs = <String>[];
    final result = await PackPipeline().run(
      config: config,
      jarInfo: jarInfo,
      log: (String line, LogLevel level) => logs.add(line),
    );

    expect(result.success, true,
        reason: '${result.message}\n${logs.join('\n')}');
    expect(File(result.outputExePath!).existsSync(), true,
        reason: result.outputExePath);

    // 用户原始 jar 字节不变（修复前模块化会往里写 module-info.class）
    final jarAfter = await File(_consoleJar).readAsBytes();
    expect(_fnv1a(jarAfter), _fnv1a(jarBefore),
        reason: '用户原始 jar 被改写了！');

    // jar 同目录不应出现 input/ 副本目录（修复前非模块化回退会留下）
    expect(Directory(p.join(p.dirname(_consoleJar), 'input')).existsSync(), false,
        reason: '用户 jar 目录被 input/ 目录污染');

    // 模块化临时目录应被清理（修复前每次运行泄漏一个）
    expect(_countModTempDirs(), leakedBefore);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

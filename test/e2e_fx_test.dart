import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jpackage_gui/models/pack_config.dart';
import 'package:jpackage_gui/services/jar_analyzer.dart';
import 'package:jpackage_gui/services/log_types.dart';
import 'package:jpackage_gui/services/pipeline.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// JavaFX 路径端到端验证：覆盖 P0-1（jdeps 必须带 JavaFX --module-path，
/// 否则 module-info 丢失 requires javafx.*）。
///
/// 非 CI 用途，依赖本机 JDK 与 JavaFX SDK，默认 skip；运行：
/// `flutter test test/e2e_fx_test.dart --dart-define=RUN_E2E=true`
const _runE2E = bool.fromEnvironment('RUN_E2E');

const _jdkPath = r'D:\develop\jdk-17.0.12';
const _root = r'E:\jpackage-gui\test_assets\e2e_p0';
const _fxSdk = r'E:\jpackage-gui\test_assets\javafx-sdk-17.0.2';

class _MockPathProvider extends PathProviderPlatform {
  final _dir =
      Directory(p.join(Directory.systemTemp.path, 'jpackage_gui_e2e_p0'));

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

  test('JavaFX jar 的 module-info 必须带上 requires javafx.*', () async {
    final jarPath = p.join(_root, 'FxProbe.jar');
    final outRoot = p.join(_root, 'run_fx');
    if (Directory(outRoot).existsSync()) {
      Directory(outRoot).deleteSync(recursive: true);
    }
    await Directory(outRoot).create(recursive: true);

    PathProviderPlatform.instance = _MockPathProvider();

    final lines = <String>[];
    void log(String line, LogLevel level) => lines.add('${level.name} $line');

    final jarInfo = await JarAnalyzer().analyze(jarPath);
    expect(jarInfo.needsJavaFxSdk, isTrue,
        reason: 'FxProbe 继承 Application，应被识别为需要 JavaFX SDK');

    final config = PackConfig(
      jarPath: jarPath,
      appName: 'FxProbe',
      appVersion: '1.0.0',
      mainClass: 'fxapp.FxProbe',
      outputDir: outRoot,
      vendor: 'e2e',
      jdkPath: _jdkPath,
      moduleName: jarInfo.moduleName,
      enableProGuard: false, // 本用例聚焦模块解析，跳过混淆以缩短耗时
      keepResources: true,
      generateMsi: false,
      javafxSdkPath: _fxSdk,
    );

    final result = await PackPipeline().run(
      config: config,
      jarInfo: jarInfo,
      log: log,
    );
    await File(p.join(outRoot, 'e2e.log')).writeAsString(lines.join('\n'));

    expect(result.success, isTrue, reason: result.message);

    // 必须走模块化：否则说明 jdeps 又退化了
    final modularLog =
        lines.any((l) => l.contains('模块化完成') && !l.contains('失败'));
    expect(modularLog, isTrue, reason: '未能完成模块化:\n${lines.join('\n')}');

    final modulesLine = File(p.join(outRoot, 'FxProbe', 'runtime', 'release'))
        .readAsStringSync()
        .split('\n')
        .firstWhere((l) => l.startsWith('MODULES='));
    // ignore: avoid_print
    print('RUNTIME $modulesLine');
    for (final mod in ['javafx.controls', 'javafx.graphics', 'javafx.base']) {
      expect(modulesLine.contains(mod), isTrue,
          reason: 'runtime MODULES 缺少 $mod -> $modulesLine');
    }

    // app/ 不应留明文 jar（class 藏在 jimage 中）
    final jarFiles = Directory(p.join(outRoot, 'FxProbe', 'app'))
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jar'))
        .toList();
    expect(jarFiles, isEmpty,
        reason: '模块化路径不应留下明文 jar: ${jarFiles.map((f) => f.path)}');
  }, skip: !_runE2E);
}

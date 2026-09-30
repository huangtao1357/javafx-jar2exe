import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jpackage_gui/models/pack_config.dart';
import 'package:jpackage_gui/services/jar_analyzer.dart';
import 'package:jpackage_gui/services/log_types.dart';
import 'package:jpackage_gui/services/pipeline.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 端到端验证：用真实 fat jar 跑完整 PackPipeline（ProGuard → jdeps → jpackage），
/// 覆盖反馈中的三个失败点（java.logging / java.sql / jdk.crypto.ec）。
///
/// 非 CI 用途，依赖本机 JDK 与测试 jar，因此默认 skip；
/// 需要时用 `flutter test test/e2e_p0_test.dart --dart-define=RUN_E2E=true` 运行。
const _runE2E = bool.fromEnvironment('RUN_E2E');

const _jdkPath = r'D:\develop\jdk-17.0.12';
const _root = r'E:\jpackage-gui\test_assets\e2e_p0';

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

  test('fat jar 打包后 runtime 含 java.logging/java.sql/jdk.crypto.ec', () async {
    final jarPath = p.join(_root, 'T8P0.jar');
    final outRoot = p.join(_root, 'run_fixed');
    if (Directory(outRoot).existsSync()) {
      Directory(outRoot).deleteSync(recursive: true);
    }
    await Directory(outRoot).create(recursive: true);

    PathProviderPlatform.instance = _MockPathProvider();

    final lines = <String>[];
    void log(String line, LogLevel level) => lines.add('${level.name} $line');

    final jarInfo = await JarAnalyzer().analyze(jarPath);
    expect(jarInfo.defaultEntry?.className, 'app.T8App');

    final config = PackConfig(
      jarPath: jarPath,
      appName: 'T8P0',
      appVersion: '1.0.0',
      mainClass: jarInfo.defaultEntry!.className,
      outputDir: outRoot,
      vendor: 'e2e',
      jdkPath: _jdkPath,
      moduleName: jarInfo.moduleName,
      enableProGuard: true,
      keepResources: true,
      generateMsi: false,
    );

    final result = await PackPipeline().run(
      config: config,
      jarInfo: jarInfo,
      log: log,
    );

    // 落盘日志便于人工核对
    await File(p.join(outRoot, 'e2e.log')).writeAsString(lines.join('\n'));

    expect(result.success, isTrue, reason: result.message);

    // 断言 1：运行时模块列表包含三个关键模块
    final release =
        File(p.join(outRoot, 'T8P0', 'runtime', 'release')).readAsStringSync();
    final modulesLine =
        release.split('\n').firstWhere((l) => l.startsWith('MODULES='));
    // ignore: avoid_print
    print('RUNTIME $modulesLine');
    for (final mod in ['java.logging', 'java.sql', 'jdk.crypto.ec']) {
      expect(modulesLine.contains(mod), isTrue,
          reason: 'runtime MODULES 缺少 $mod -> $modulesLine');
    }

    // 断言 2：走的是模块化路径（app/ 下无明文 jar，class 藏在 jimage 里）
    final appDir = Directory(p.join(outRoot, 'T8P0', 'app'));
    final jarFiles = appDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jar'))
        .toList();
    expect(jarFiles, isEmpty,
        reason: '模块化路径不应在 app/ 留下明文 jar: ${jarFiles.map((f) => f.path)}');
    expect(File(p.join(outRoot, 'T8P0', 'runtime', 'lib', 'modules')).existsSync(),
        isTrue);
  }, skip: !_runE2E);
}

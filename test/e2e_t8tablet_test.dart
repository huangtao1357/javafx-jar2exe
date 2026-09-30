import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jpackage_gui/models/pack_config.dart';
import 'package:jpackage_gui/services/jar_analyzer.dart';
import 'package:jpackage_gui/services/log_types.dart';
import 'package:jpackage_gui/services/pipeline.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 针对真实问题 jar（T8TabletFrigLogTranslate）的端到端回归：
/// 该 jar 的 fat jar 内含 fastjson 的半个可选集成（javax.ws.rs.ext /
/// org.glassfish.jersey.internal.spi），jdeps 会生成无法编译的 provides 声明，
/// 旧逻辑因此退回非模块化并从 --add-modules 丢掉 java.logging，运行期登录崩溃。
///
/// 默认 skip；运行：flutter test test/e2e_t8tablet_test.dart --dart-define=RUN_E2E=true
const _runE2E = bool.fromEnvironment('RUN_E2E');

const _jdkPath = r'D:\develop\jdk-17.0.12';
const _fxSdk = r'E:\jpackage-gui\test_assets\javafx-sdk-17.0.2';
const _srcJar = r'E:\2026\9月\9.30\T8TabletFrigLogTranslate.jar';
const _outRoot = r'E:\jpackage-gui\test_assets\e2e_t8tablet';

class _MockPathProvider extends PathProviderPlatform {
  final _dir =
      Directory(p.join(Directory.systemTemp.path, 'jpackage_gui_e2e_t8t'));

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

  test('T8TabletFrigLogTranslate：剔除无效 provides 后模块化成功且 java.logging 进入 runtime',
      () async {
    final outRoot = _outRoot;
    if (Directory(outRoot).existsSync()) {
      Directory(outRoot).deleteSync(recursive: true);
    }
    await Directory(outRoot).create(recursive: true);

    PathProviderPlatform.instance = _MockPathProvider();

    final lines = <String>[];
    void log(String line, LogLevel level) => lines.add('${level.name} $line');

    final jarInfo = await JarAnalyzer().analyze(_srcJar);
    final config = PackConfig(
      jarPath: _srcJar,
      appName: 'T8TabletFrigLogTranslate',
      appVersion: '1.0.0',
      mainClass: 'sample.Launcher',
      outputDir: outRoot,
      vendor: '',
      jdkPath: _jdkPath,
      moduleName: jarInfo.moduleName,
      enableProGuard: true, // 与用户实际流程一致
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

    final joined = lines.join('\n');
    // ignore: avoid_print
    print('DROPPED_PROVIDES ${lines.where((l) => l.contains('provides')).join(' | ')}');
    // ignore: avoid_print
    print('PATH ${joined.contains('模块化完成') ? 'modular' : 'non-modular-fallback'}');

    // 断言 1：模块化不能因 provides 编译失败而回退
    //（本用例的 jar 含 fastjson 半个可选集成，旧逻辑必然失败）
    expect(joined.contains('已剔除 4 条无法解析的 provides 声明'), isTrue,
        reason: '未剔除无效 provides:\n$joined');
    expect(joined.contains('模块化完成'), isTrue, reason: '仍退回非模块化:\n$joined');

    // 断言 2：runtime 必须含 java.logging / java.sql / jdk.crypto.ec
    final modulesLine = File(
      p.join(outRoot, 'T8TabletFrigLogTranslate', 'runtime', 'release'),
    )
        .readAsStringSync()
        .split('\n')
        .firstWhere((l) => l.startsWith('MODULES='));
    // ignore: avoid_print
    print('RUNTIME $modulesLine');
    for (final mod in ['java.logging', 'java.sql', 'jdk.crypto.ec']) {
      expect(modulesLine.contains(mod), isTrue,
          reason: 'runtime MODULES 缺少 $mod -> $modulesLine');
    }

    // 断言 3：app/ 下无明文 jar
    final jarFiles = Directory(
      p.join(outRoot, 'T8TabletFrigLogTranslate', 'app'),
    )
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jar'))
        .toList();
    expect(jarFiles, isEmpty,
        reason: '模块化路径不应留下明文 jar: ${jarFiles.map((f) => f.path)}');
  }, skip: !_runE2E, timeout: const Timeout(Duration(minutes: 10)));
}

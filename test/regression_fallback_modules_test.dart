import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jpackage_gui/models/pack_config.dart';
import 'package:jpackage_gui/services/jar_analyzer.dart';
import 'package:jpackage_gui/services/log_types.dart';
import 'package:jpackage_gui/services/pipeline.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 回归：模块化失败退回非模块化时，jdeps 检测到的模块**仍必须**进入
/// `--add-modules`。
///
/// 这正是 T8TabletFrigLogTranslate 登录崩溃的成因：旧逻辑写成
/// `if (useModular) addAll(requiredModules)`，一旦回退就把 java.logging 丢掉，
/// 而 classpath 应用没有 module-info 提供依赖闭包，jlink 便只链入 JavaFX 闭包，
/// 运行期 okhttp 静态初始化抛 NoClassDefFoundError: java/util/logging/Logger。
///
/// 用例用带失效 META-INF/services 的 fat jar 强制触发 jdeps 失败（→ 非模块化），
/// 再断言 runtime 仍含 java.logging / java.sql / jdk.crypto.ec。
///
/// 默认 skip；运行：
/// `flutter test test/regression_fallback_modules_test.dart --dart-define=RUN_E2E=true`
const _runE2E = bool.fromEnvironment('RUN_E2E');

const _jdkPath = r'D:\develop\jdk-17.0.12';
const _root = r'E:\jpackage-gui\test_assets\e2e_p0';
const _jar = r'E:\jpackage-gui\test_assets\e2e_p0\T8BrokenServices.jar';

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

  test('非模块化回退路径也必须把 jdeps 检测到的模块并入 --add-modules', () async {
    if (!File(_jar).existsSync()) {
      fail('缺少测试 jar: $_jar（需先构建，见 test_assets/e2e_p0 生成脚本）');
    }

    final outRoot = p.join(_root, 'run_fallback');
    if (Directory(outRoot).existsSync()) {
      Directory(outRoot).deleteSync(recursive: true);
    }
    await Directory(outRoot).create(recursive: true);

    PathProviderPlatform.instance = _MockPathProvider();

    final lines = <String>[];
    void log(String line, LogLevel level) => lines.add('${level.name} $line');

    final jarInfo = await JarAnalyzer().analyze(_jar);
    final config = PackConfig(
      jarPath: _jar,
      appName: 'T8BrokenServices',
      appVersion: '1.0.0',
      mainClass: jarInfo.defaultEntry!.className,
      outputDir: outRoot,
      vendor: 'e2e',
      jdkPath: _jdkPath,
      moduleName: jarInfo.moduleName,
      enableProGuard: false, // 聚焦回退路径，省去混淆耗时
      keepResources: true,
      generateMsi: false,
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
    print('PATH ${joined.contains('模块化完成') ? 'modular' : 'non-modular-fallback'}');

    // 前置条件：本用例必须真的走了回退路径，否则断言失去意义
    expect(joined.contains('模块化完成'), isFalse,
        reason: '本用例需要触发非模块化回退，但模块化成功了');

    // 断言：jdeps 检测到的模块仍进入 --add-modules
    final addModulesLine = lines.firstWhere(
      (l) => l.contains('[jlink] --add-modules'),
      orElse: () => '',
    );
    // ignore: avoid_print
    print('ADD_MODULES $addModulesLine');
    for (final mod in ['java.logging', 'java.sql']) {
      expect(addModulesLine.contains(mod), isTrue,
          reason: '非模块化回退时 $mod 被从 --add-modules 丢失: $addModulesLine');
    }

    // 断言：产物 runtime 实际包含这些模块
    final modulesLine =
        File(p.join(outRoot, 'T8BrokenServices', 'runtime', 'release'))
            .readAsStringSync()
            .split('\n')
            .firstWhere((l) => l.startsWith('MODULES='));
    // ignore: avoid_print
    print('RUNTIME $modulesLine');
    for (final mod in ['java.logging', 'java.sql', 'jdk.crypto.ec']) {
      expect(modulesLine.contains(mod), isTrue,
          reason: 'runtime MODULES 缺少 $mod -> $modulesLine');
    }
  }, skip: !_runE2E, timeout: const Timeout(Duration(minutes: 10)));
}

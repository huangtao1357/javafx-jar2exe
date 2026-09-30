import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jpackage_gui/models/pack_config.dart';
import 'package:jpackage_gui/services/jar_analyzer.dart';
import 'package:jpackage_gui/services/log_types.dart';
import 'package:jpackage_gui/services/pipeline.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// classpath（默认）打包路径的**真实启动**回归：
/// 用反馈方真实 jar 走默认流程，然后真的把产物 exe 跑起来，断言它能进入主界面
/// （JavaFX 启动成功、FXML 与图片资源都能加载）。
///
/// 背景：模块化打包会让 Class.getResource 失去系统类加载器回退，
/// `new Image("logo/x.png")` 这类非 package 资源直接找不到，应用启动即崩。
/// 因此默认改为 classpath 打包，本用例锁住「默认产物必须能起来」。
///
/// 默认 skip；运行：flutter test test/e2e_launch_test.dart --dart-define=RUN_E2E=true
const _runE2E = bool.fromEnvironment('RUN_E2E');

const _jdkPath = r'D:\develop\jdk-17.0.12';
const _fxSdk = r'E:\jpackage-gui\test_assets\javafx-sdk-17.0.2';
const _srcJar = r'E:\2026\9月\9.30\T8TabletFrigLogTranslate.jar';
const _appName = 'T8TabletFrigLogTranslate';
const _outRoot = r'E:\jpackage-gui\test_assets\e2e_launch';

class _MockPathProvider extends PathProviderPlatform {
  final _dir =
      Directory(p.join(Directory.systemTemp.path, 'jpackage_gui_e2e_launch'));

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

  test('默认 classpath 打包的产物必须能真正启动（JavaFX + FXML + 图片资源）', () async {
    if (!File(_srcJar).existsSync()) {
      fail('缺少测试 jar: $_srcJar');
    }

    // 上一次运行可能残留进程占用 runtime 文件
    await Process.run('taskkill', [
      '/IM', '$_appName.exe', '/F', '/T',
    ], runInShell: true);
    await Future.delayed(const Duration(milliseconds: 800));

    if (Directory(_outRoot).existsSync()) {
      Directory(_outRoot).deleteSync(recursive: true);
    }
    await Directory(_outRoot).create(recursive: true);

    PathProviderPlatform.instance = _MockPathProvider();

    final lines = <String>[];
    void log(String line, LogLevel level) => lines.add('${level.name} $line');

    final jarInfo = await JarAnalyzer().analyze(_srcJar);
    final config = PackConfig(
      jarPath: _srcJar,
      appName: _appName,
      appVersion: '1.0.0',
      mainClass: 'sample.Launcher',
      outputDir: _outRoot,
      vendor: '',
      jdkPath: _jdkPath,
      moduleName: jarInfo.moduleName,
      enableProGuard: true,
      keepResources: true,
      generateMsi: false,
      javafxSdkPath: _fxSdk,
      enableModularPackaging: false, // 默认行为
    );

    final result = await PackPipeline().run(
      config: config,
      jarInfo: jarInfo,
      log: log,
    );
    await File(p.join(_outRoot, 'e2e.log')).writeAsString(lines.join('\n'));
    expect(result.success, isTrue, reason: result.message);

    final joined = lines.join('\n');
    // ignore: avoid_print
    print('PATH ${joined.contains('模块化完成') ? 'modular' : 'classpath'}');
    expect(joined.contains('跳过模块化'), isTrue, reason: '默认应走 classpath');

    // runtime 必须含应用依赖的模块
    final modulesLine =
        File(p.join(_outRoot, _appName, 'runtime', 'release'))
            .readAsStringSync()
            .split('\n')
            .firstWhere((l) => l.startsWith('MODULES='));
    // ignore: avoid_print
    print('RUNTIME $modulesLine');
    for (final mod in ['java.logging', 'java.sql', 'jdk.crypto.ec']) {
      expect(modulesLine.contains(mod), isTrue,
          reason: 'runtime 缺少 $mod -> $modulesLine');
    }

    // 关键：真的启动产物，并捕获 stdout。
    // 用 javaw 无法拿输出，因此直接跑 exe 并读它的 stdout。
    final exe = p.join(_outRoot, _appName, '$_appName.exe');
    expect(File(exe).existsSync(), isTrue, reason: '未生成 exe: $exe');

    final proc = await Process.start(exe, const [], runInShell: false);
    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    proc.stdout.transform(const SystemEncoding().decoder).listen(stdoutBuf.write);
    proc.stderr.transform(const SystemEncoding().decoder).listen(stderrBuf.write);

    // 等 JavaFX 起窗口；若加载 FXML/资源失败会在数秒内退出
    final exited = await proc.exitCode.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -999; // 仍在运行 = 启动成功，没有崩
      },
    );

    final out = stdoutBuf.toString();
    final err = stderrBuf.toString();
    // ignore: avoid_print
    print('EXIT $exited');
    if (out.trim().isNotEmpty) {
      // ignore: avoid_print
      print('STDOUT ${out.trim().split('\n').take(6).join(' / ')}');
    }
    if (err.trim().isNotEmpty) {
      // ignore: avoid_print
      print('STDERR ${err.trim().split('\n').take(6).join(' / ')}');
    }

    // 断言：不能出现资源加载失败 / 启动异常
    for (final bad in [
      'Invalid URL',
      'LoadException',
      'Failed to launch JVM',
      'NoClassDefFoundError',
      'Exception in Application start method',
    ]) {
      expect(err.contains(bad) || out.contains(bad), isFalse,
          reason: '产物启动报错 [$bad]\nSTDOUT:\n$out\nSTDERR:\n$err');
    }
    expect(exited, -999, reason: '产物提前退出（exit=$exited），说明启动失败');
  }, skip: !_runE2E, timeout: const Timeout(Duration(minutes: 10)));
}

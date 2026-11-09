import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpackage_gui/models/pack_config.dart';
import 'package:jpackage_gui/viewmodels/pack_viewmodel.dart';
import 'package:path/path.dart' as p;

void main() {
  final root = Directory.current.path;
  final jarA = p.join(root, 'projA', 'out', 'artifacts', 'appA.jar');
  final jarB = p.join(root, 'projB', 'out', 'artifacts', 'appB.jar');
  final fallback = p.join(root, 'output');
  final custom = p.join(root, 'my_builds');

  group('输出目录跟随所选 jar 的同级目录', () {
    test('未选择 jar 时使用兜底目录', () {
      final config = PackConfig();
      config.syncOutputDir(fallback);
      expect(config.outputDir, fallback);
    });

    test('切换 jar 时覆盖上一个项目残留的输出目录', () {
      final config = PackConfig(outputDir: p.dirname(jarA));
      config.jarPath = jarA;
      config.syncOutputDir(fallback);
      expect(config.outputDir, p.dirname(jarA));

      config.jarPath = jarB;
      config.syncOutputDir(fallback);
      expect(config.outputDir, p.dirname(jarB));
    });

    test('手动指定输出目录后不再被 jar 切换覆盖', () {
      final config = PackConfig(outputDirFollowsJar: false, outputDir: custom);
      config.jarPath = jarA;
      config.syncOutputDir(fallback);
      expect(config.outputDir, custom);
    });

    test('一键恢复跟随会重新对齐 jar 所在目录', () {
      final config = PackConfig(outputDirFollowsJar: false, outputDir: custom);
      config.followJarOutputDir(jarB);
      expect(config.outputDirFollowsJar, isTrue);
      expect(config.outputDir, p.dirname(jarB));
    });

    test('旧版本配置缺少标记字段时默认自动跟随', () {
      final config = PackConfig.fromJson({
        'jarPath': jarA,
        'outputDir': custom,
      });
      expect(config.outputDirFollowsJar, isTrue);
      config.syncOutputDir(fallback);
      expect(config.outputDir, p.dirname(jarA));
    });

    test('手动标记随配置持久化', () {
      final config = PackConfig(outputDirFollowsJar: false);
      final restored = PackConfig.fromJson(config.toJson());
      expect(restored.outputDirFollowsJar, isFalse);
    });

    test('ViewModel 选择新 jar 会刷新输出目录', () async {
      final vm = PackViewModel();
      vm.config.jarPath = jarA;
      vm.config.outputDir = p.dirname(jarA);
      // 传入不存在的 jar：解析失败不影响输出目录的默认推导
      await vm.selectJar(jarB);
      expect(vm.config.outputDir, p.dirname(jarB));
    });

    test('ViewModel 手动改输出目录后保留，可再恢复跟随', () {
      final vm = PackViewModel();
      vm.config.jarPath = jarA;
      vm.config.syncOutputDir(fallback);

      vm.updateConfig((x) => x.outputDir = custom);
      expect(vm.config.outputDirFollowsJar, isFalse);

      vm.config.jarPath = jarB;
      vm.config.syncOutputDir(fallback);
      expect(vm.config.outputDir, custom);

      vm.useJarDirectoryAsOutput();
      expect(vm.config.outputDirFollowsJar, isTrue);
      expect(vm.config.outputDir, p.dirname(jarB));
    });
  });
}

import 'dart:io';
import 'package:path/path.dart' as p;
import 'log_types.dart';
import 'process_runner.dart';

class JPackageResult {
  final bool success;
  final String? message;
  const JPackageResult({required this.success, this.message});
}

class JPackageService {
  /// jpackage 在未显式指定 --jlink-options 时使用的默认值。
  /// 注意：--jlink-options 是**整体替换**而非追加，因此一旦传了自定义选项，
  /// 这些默认值就会全部失效（实测因此白扔约 4MB 体积），必须显式补回。
  static const _defaultJlinkOptions =
      '--strip-native-commands --strip-debug --no-man-pages --no-header-files';

  /// 合并 jlink 选项：先补回 jpackage 默认值，再追加压缩与用户自定义选项。
  String _jlinkOptions({String extra = ''}) {
    final parts = <String>[_defaultJlinkOptions, '--compress=2'];
    if (extra.trim().isNotEmpty) parts.add(extra.trim());
    return parts.join(' ');
  }

  Future<JPackageResult> buildAppImage({
    required String jpackagePath,
    required String appName,
    required String appVersion,
    required String moduleName,
    required String mainClass,
    required String modulePath,
    required String outputDir,
    required String vendor,
    String? iconPath,
    String javaOptions = '',
    String appArguments = '',
    String? extraModulePath,
    String? addModules,
    required LogSink log,
    ProcessHandle? handle,
  }) async {
    // --module-path 是**路径列表**，必须用路径列表分隔符（Windows 为 ';'）拼接。
    // 旧实现误用 Platform.pathSeparator（Windows 下是 '\'），得到
    // "<workdir>\<javafx-lib>" 这种非法路径，jpackage 直接报
    // ConfigException: Illegal char <:>，模块化打包整体失败。
    final effectiveModulePath = (extraModulePath != null && extraModulePath.isNotEmpty)
        ? '$modulePath${Platform.isWindows ? ';' : ':'}$extraModulePath'
        : modulePath;
    final args = <String>[
      '--type', 'app-image',
      '--name', appName,
      '--app-version', appVersion,
      '--module', '$moduleName/$mainClass',
      '--module-path', effectiveModulePath,
      '--dest', outputDir,
      '--vendor', vendor,
      '--verbose',
      // jpackage 默认的 strip 选项必须显式补回：--jlink-options 是整体替换
      '--jlink-options', _jlinkOptions(),
    ];
    if (addModules != null && addModules.isNotEmpty) {
      args.addAll(['--add-modules', addModules]);
    }
    if (iconPath != null && iconPath.isNotEmpty) {
      args.addAll(['--icon', iconPath]);
    }
    if (javaOptions.isNotEmpty) {
      for (final opt in javaOptions.split('\n').where((s) => s.trim().isNotEmpty)) {
        args.addAll(['--java-options', opt.trim()]);
      }
    }
    if (appArguments.isNotEmpty) {
      args.addAll(['--arguments', appArguments]);
    }

    log('[jpackage] $jpackagePath ${args.join(' ')}', LogLevel.command);
    String? errorMsg;
    final ok = await runProcess(
      jpackagePath,
      args,
      log: log,
      tag: '[jpackage]',
      handle: handle,
      onError: (msg) => errorMsg = msg,
    );
    if (!ok) {
      if (errorMsg != null && errorMsg!.contains('AccessDeniedException')) {
        return const JPackageResult(
          success: false,
          message: '文件被锁定（AccessDeniedException），可能是上一次生成的 exe 仍在运行或被杀毒软件拦截。请关闭正在运行的程序，或将输出目录添加到杀毒软件白名单后重试。',
        );
      }
      return const JPackageResult(success: false, message: 'jpackage 构建失败');
    }
    return const JPackageResult(success: true);
  }

  Future<JPackageResult> buildAppImageNonModular({
    required String jpackagePath,
    required String appName,
    required String appVersion,
    required String mainJar,
    required String mainClass,
    required String inputDir,
    required String outputDir,
    required String vendor,
    String? iconPath,
    String javaOptions = '',
    String appArguments = '',
    String? modulePath,
    String? addModules,
    required LogSink log,
    ProcessHandle? handle,
  }) async {
    final args = <String>[
      '--type', 'app-image',
      '--name', appName,
      '--app-version', appVersion,
      '--input', inputDir,
      '--main-jar', p.basename(mainJar),
      '--main-class', mainClass,
      '--dest', outputDir,
      '--vendor', vendor,
      '--verbose',
      // jpackage 默认的 strip 选项必须显式补回：--jlink-options 是整体替换
      '--jlink-options', _jlinkOptions(),
    ];
    // JavaFX 等外部模块：交给 jlink 链进 runtime，不要放进 --input classpath
    if (modulePath != null && modulePath.isNotEmpty) {
      args.addAll(['--module-path', modulePath]);
    }
    if (addModules != null && addModules.isNotEmpty) {
      args.addAll(['--add-modules', addModules]);
    }
    if (iconPath != null && iconPath.isNotEmpty) {
      args.addAll(['--icon', iconPath]);
    }
    if (javaOptions.isNotEmpty) {
      for (final opt in javaOptions.split('\n').where((s) => s.trim().isNotEmpty)) {
        args.addAll(['--java-options', opt.trim()]);
      }
    }
    if (appArguments.isNotEmpty) {
      args.addAll(['--arguments', appArguments]);
    }

    log('[jpackage] $jpackagePath ${args.join(' ')}', LogLevel.command);
    String? errorMsg;
    final ok = await runProcess(
      jpackagePath,
      args,
      log: log,
      tag: '[jpackage]',
      handle: handle,
      onError: (msg) => errorMsg = msg,
    );
    if (!ok) {
      if (errorMsg != null && errorMsg!.contains('AccessDeniedException')) {
        return const JPackageResult(
          success: false,
          message: '文件被锁定（AccessDeniedException），可能是上一次生成的 exe 仍在运行或被杀毒软件拦截。请关闭正在运行的程序，或将输出目录添加到杀毒软件白名单后重试。',
        );
      }
      return const JPackageResult(success: false, message: 'jpackage 非模块化构建失败');
    }
    return const JPackageResult(success: true);
  }

  Future<JPackageResult> buildMsi({
    required String jpackagePath,
    required String appName,
    required String appVersion,
    required String appImageDir,
    required String outputDir,
    required String vendor,
    required LogSink log,
    ProcessHandle? handle,
  }) async {
    final args = <String>[
      '--type', 'msi',
      '--name', appName,
      '--app-version', appVersion,
      '--app-image', appImageDir,
      '--dest', outputDir,
      '--vendor', vendor,
      '--win-per-user-install',
      '--verbose',
    ];

    log('[jpackage] $jpackagePath ${args.join(' ')}', LogLevel.command);
    final ok = await runProcess(
      jpackagePath,
      args,
      log: log,
      tag: '[jpackage]',
      handle: handle,
    );
    if (!ok) {
      return const JPackageResult(success: false, message: 'msi 安装包生成失败');
    }
    return const JPackageResult(success: true);
  }
}

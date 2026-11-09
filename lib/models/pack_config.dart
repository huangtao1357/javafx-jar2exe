import 'package:path/path.dart' as p;
import 'jar_info.dart';

class PackConfig {
  String jarPath;
  String appName;
  String appVersion;
  String mainClass;
  String? iconPath;
  String outputDir;
  /// 输出目录是否自动跟随所选 jar 所在目录；用户手动修改输出目录后为 false。
  bool outputDirFollowsJar;
  String vendor;
  String jdkPath;
  String moduleName;
  bool generateMsi;
  String javaOptions;
  String appArguments;
  bool enableProGuard;
  bool keepResources;
  String? javafxSdkPath;
  String javafxModules;
  bool stripUnusedJavaFxDlls;

  /// 是否尝试模块化打包（class 隐藏进 jimage）。
  ///
  /// 默认 **false**：模块化会把应用变成 JPMS 命名模块，而大量 JavaFX 应用把资源
  /// 放在非 package 目录下（如 `logo/x.png`、`fxml/a.fxml`）并用
  /// `new Image("logo/x.png")` 加载——在命名模块里 Class.getResource 不再回退到
  /// 系统类加载器，资源直接找不到，应用启动即抛
  /// `IllegalArgumentException: Invalid URL or resource not found`。
  /// 实测：同一应用 classpath 模式正常、模块化模式必然失败。
  /// 因此默认关闭；确实需要隐藏 class 时再显式开启并自行验证资源加载。
  bool enableModularPackaging;

  PackConfig({
    this.jarPath = '',
    this.appName = '',
    this.appVersion = '1.0.0',
    this.mainClass = '',
    this.iconPath,
    this.outputDir = '',
    this.outputDirFollowsJar = true,
    this.vendor = '',
    this.jdkPath = '',
    this.moduleName = '',
    this.generateMsi = false,
    this.javaOptions = '',
    this.appArguments = '',
    this.enableProGuard = true,
    this.keepResources = true,
    this.javafxSdkPath,
    this.javafxModules = 'javafx.controls,javafx.fxml,javafx.graphics',
    this.stripUnusedJavaFxDlls = true,
    this.enableModularPackaging = false,
  });

  String? validate() {
    if (jarPath.isEmpty) return '请选择 jar 文件';
    if (appName.isEmpty) return '请填写应用名称';
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(appName)) {
      return r'应用名称包含非法字符（\ / : * ? " < > |）';
    }
    if (appName.endsWith('.') || appName.endsWith(' ')) {
      return '应用名称不能以 "." 或空格结尾';
    }
    if (appVersion.isEmpty) return '请填写应用版本号';
    // jpackage 只接受点分整数版本号，否则中途抛 "版本包含无效组件" 的晦涩错误
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(appVersion)) {
      return '应用版本号格式无效：需为点分数字（如 1.0.0），不能带 -beta、+build 等后缀';
    }
    if (mainClass.isEmpty) return '请选择或输入 Main-Class';
    if (outputDir.isEmpty) return '请选择输出目录';
    if (jdkPath.isEmpty) return '未检测到 JDK，请手动指定 JDK 路径';
    return null;
  }

  Map<String, dynamic> toJson() => {
        'jarPath': jarPath,
        'appName': appName,
        'appVersion': appVersion,
        'mainClass': mainClass,
        'iconPath': iconPath,
        'outputDir': outputDir,
        'outputDirFollowsJar': outputDirFollowsJar,
        'vendor': vendor,
        'jdkPath': jdkPath,
        'moduleName': moduleName,
        'generateMsi': generateMsi,
        'javaOptions': javaOptions,
        'appArguments': appArguments,
        'enableProGuard': enableProGuard,
        'keepResources': keepResources,
        'javafxSdkPath': javafxSdkPath,
        'javafxModules': javafxModules,
        'stripUnusedJavaFxDlls': stripUnusedJavaFxDlls,
        'enableModularPackaging': enableModularPackaging,
      };

  factory PackConfig.fromJson(Map<String, dynamic> json) => PackConfig(
        jarPath: json['jarPath'] as String? ?? '',
        appName: json['appName'] as String? ?? '',
        appVersion: json['appVersion'] as String? ?? '1.0.0',
        mainClass: json['mainClass'] as String? ?? '',
        iconPath: json['iconPath'] as String?,
        outputDir: json['outputDir'] as String? ?? '',
        // 旧版本配置无此字段：默认跟随，避免沿用上一个项目的输出目录
        outputDirFollowsJar: json['outputDirFollowsJar'] as bool? ?? true,
        vendor: json['vendor'] as String? ?? '',
        jdkPath: json['jdkPath'] as String? ?? '',
        moduleName: json['moduleName'] as String? ?? '',
        generateMsi: json['generateMsi'] as bool? ?? false,
        javaOptions: json['javaOptions'] as String? ?? '',
        appArguments: json['appArguments'] as String? ?? '',
        enableProGuard: json['enableProGuard'] as bool? ?? true,
        keepResources: json['keepResources'] as bool? ?? true,
        javafxSdkPath: json['javafxSdkPath'] as String?,
        javafxModules: json['javafxModules'] as String? ?? 'javafx.controls,javafx.fxml,javafx.graphics',
        stripUnusedJavaFxDlls: json['stripUnusedJavaFxDlls'] as bool? ?? true,
        enableModularPackaging: json['enableModularPackaging'] as bool? ?? false,
      );

  PackConfig copy() => PackConfig.fromJson(toJson());

  /// jar 文件所在的同级目录，用作默认输出目录。
  static String jarOutputDir(String jarPath) =>
      p.dirname(p.normalize(p.absolute(jarPath)));

  /// 按当前 [jarPath] 刷新输出目录：自动跟随状态下优先使用 jar 所在目录，
  /// 未选择 jar 时退回 [fallbackDir]。
  void syncOutputDir(String fallbackDir) {
    if (!outputDirFollowsJar) {
      if (outputDir.isEmpty) outputDir = fallbackDir;
      return;
    }
    outputDir = jarPath.isNotEmpty ? jarOutputDir(jarPath) : fallbackDir;
  }

  /// 重新启用「输出目录跟随 jar 所在目录」并立即刷新。
  void followJarOutputDir(String jarPath) {
    outputDirFollowsJar = true;
    outputDir = jarOutputDir(jarPath);
  }

  void applyJarInfo(JarInfo info) {
    jarPath = info.path;
    if (moduleName.isEmpty) moduleName = info.moduleName;
    // 始终根据 jar 文件名更新应用名称
    final base = info.path.split(RegExp(r'[/\\]')).last;
    appName = base.endsWith('.jar') ? base.substring(0, base.length - 4) : base;
    final entry = info.defaultEntry;
    if (entry != null) mainClass = entry.className;
  }
}

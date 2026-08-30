import 'jar_info.dart';

class PackConfig {
  String jarPath;
  String appName;
  String appVersion;
  String mainClass;
  String? iconPath;
  String outputDir;
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

  PackConfig({
    this.jarPath = '',
    this.appName = '',
    this.appVersion = '1.0.0',
    this.mainClass = '',
    this.iconPath,
    this.outputDir = '',
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
      };

  factory PackConfig.fromJson(Map<String, dynamic> json) => PackConfig(
        jarPath: json['jarPath'] as String? ?? '',
        appName: json['appName'] as String? ?? '',
        appVersion: json['appVersion'] as String? ?? '1.0.0',
        mainClass: json['mainClass'] as String? ?? '',
        iconPath: json['iconPath'] as String?,
        outputDir: json['outputDir'] as String? ?? '',
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
      );

  PackConfig copy() => PackConfig.fromJson(toJson());

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

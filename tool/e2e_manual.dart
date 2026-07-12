import 'dart:io';

// 端到端验证脚本（不依赖 Flutter plugin，仅用 dart:io）
// 验证 jar → ProGuard 混淆 → jdeps 模块化 → jpackage 打包 这条链路在 JDK 17 上能成功产出 exe
Future<void> main() async {
  final jdkPath = r'D:\develop\jdk-17.0.12';
  final bin = '$jdkPath\\bin';
  final jarPath = r'e:\jpackage-gui\test_assets\consoleapp.jar';
  final workDir = r'e:\jpackage-gui\test_assets\pipeline_run';
  final outDir = '$workDir\\out';
  final obfuscated = '$workDir\\obfuscated.jar';
  final moduleName = 'consoleapp';
  final mainClass = 'demo.ConsoleApp';

  await Directory(workDir).create(recursive: true);
  await Directory(outDir).create(recursive: true);

  // 1. ProGuard 混淆
  final proguardJar = r'e:\jpackage-gui\assets\tools\proguard.jar';
  final proConfig = '''
# Generated
-injars "$jarPath"
-outjars "$obfuscated"
-dontoptimize
-dontwarn
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,SourceFile,LineNumberTable

-keep public class $mainClass {
    public static void main(java.lang.String[]);
}

-keep public class * extends javafx.application.Application {
    public static void main(java.lang.String[]);
    public void start(javafx.stage.Stage);
}

-keep class * {
    @javafx.fxml.FXML <fields>;
}

-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
''';
  final proFile = '$workDir\\proguard.pro';
  await File(proFile).writeAsString(proConfig);
  log('Run ProGuard');
  final pg = await Process.run('$bin\\java.exe', ['-jar', proguardJar, '@$proFile']);
  stdout.writeln('pg stdout: ${pg.stdout}');
  stderr.writeln('pg stderr: ${pg.stderr}');
  if (pg.exitCode != 0) {
    stderr.writeln('ProGuard failed');
    exit(1);
  }
  if (!File(obfuscated).existsSync()) {
    stderr.writeln('obfuscated.jar not produced');
    exit(1);
  }
  log('obfuscated: ${File(obfuscated).lengthSync()} bytes');

  // 2. jdeps 生成 module-info
  log('Run jdeps');
  final jd = await Process.run('$bin\\jdeps.exe', ['--generate-module-info', workDir, obfuscated]);
  stdout.writeln('jd stdout: ${jd.stdout}');
  stderr.writeln('jd stderr: ${jd.stderr}');
  if (jd.exitCode != 0) {
    stderr.writeln('jdeps failed');
    exit(1);
  }

  // find module-info.java
  final modInfoFile = await _findFile(workDir, 'module-info.java');
  if (modInfoFile == null) {
    stderr.writeln('module-info.java not found');
    exit(1);
  }
  final content = await File(modInfoFile).readAsString();
  final m = RegExp(r'module\s+(\S+)\s*\{').firstMatch(content);
  final realModuleName = m?.group(1) ?? moduleName;
  log('Real module name: $realModuleName');

  // 3. javac module-info
  log('Run javac');
  final jc = await Process.run('$bin\\javac.exe', [
    '--patch-module', '$realModuleName=$obfuscated',
    '-d', workDir,
    modInfoFile,
  ]);
  stdout.writeln('jc stdout: ${jc.stdout}');
  stderr.writeln('jc stderr: ${jc.stderr}');
  if (jc.exitCode != 0) {
    stderr.writeln('javac failed');
    exit(1);
  }
  final modClass = '$workDir\\module-info.class';
  if (!File(modClass).existsSync()) {
    stderr.writeln('module-info.class not produced');
    exit(1);
  }

  // 4. jar update
  log('Run jar --update');
  final ju = await Process.run('$bin\\jar.exe', [
    '--update',
    '--file=$obfuscated',
    '--module-version=1.0',
    '-C', workDir,
    'module-info.class',
  ]);
  stdout.writeln('ju stdout: ${ju.stdout}');
  stderr.writeln('ju stderr: ${ju.stderr}');
  if (ju.exitCode != 0) {
    stderr.writeln('jar update failed');
    exit(1);
  }
  // 清理 jdeps 生成的中间目录，避免 module-path 双重发现
  final obfSubDir = Directory('$workDir\\obfuscated');
  if (await obfSubDir.exists()) {
    await obfSubDir.delete(recursive: true);
  }
  // 删除 workDir 下散落的 module-info.class，避免 jpackage 把 workDir 当作 exploded module
  final strayModInfo = File('$workDir\\module-info.class');
  if (await strayModInfo.exists()) {
    await strayModInfo.delete();
  }

  // 5. jpackage
  log('Run jpackage');
  final jp = await Process.run('$bin\\jpackage.exe', [
    '--type', 'app-image',
    '--name', 'consoleapp',
    '--app-version', '1.0.0',
    '--module', '$realModuleName/$mainClass',
    '--module-path', workDir,
    '--dest', outDir,
    '--vendor', 'TestVendor',
    '--verbose',
  ]);
  stdout.writeln('jp stdout: ${jp.stdout}');
  stderr.writeln('jp stderr: ${jp.stderr}');
  if (jp.exitCode != 0) {
    stderr.writeln('jpackage failed');
    exit(1);
  }

  final exePath = '$outDir\\consoleapp\\consoleapp.exe';
  final modulesPath = '$outDir\\consoleapp\\runtime\\lib\\modules';
  log('exe exists: ${File(exePath).existsSync()} at $exePath');
  log('jimage exists: ${File(modulesPath).existsSync()} at $modulesPath');

  if (File(modulesPath).existsSync()) {
    log('class 已隐藏在 jimage 中');
  }

  exit(0);
}

void log(String msg) {
  stdout.writeln('[smoke] $msg');
}

Future<String?> _findFile(String dir, String suffix) async {
  final entries = await Directory(dir).list(recursive: true).toList();
  for (final e in entries) {
    if (e is File && e.path.endsWith(suffix)) return e.path;
  }
  return null;
}

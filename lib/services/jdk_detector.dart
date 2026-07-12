import 'dart:io';
import 'package:path/path.dart' as p;

class JdkInfo {
  final String jdkPath;
  final String jpackagePath;
  final String javaPath;
  final String javacPath;
  final String jdepsPath;
  final String jarPath;

  const JdkInfo({
    required this.jdkPath,
    required this.jpackagePath,
    required this.javaPath,
    required this.javacPath,
    required this.jdepsPath,
    required this.jarPath,
  });
}

class JdkDetector {
  static Future<JdkInfo?> detect() async {
    final envJavaHome = Platform.environment['JAVA_HOME'];
    if (envJavaHome != null && envJavaHome.isNotEmpty) {
      final info = _fromJdkRoot(envJavaHome);
      if (info != null) return info;
    }

    final lookup = await _lookUpInPath('jpackage');
    if (lookup != null) {
      final binDir = p.dirname(lookup);
      final jdkRoot = p.dirname(binDir);
      final info = _fromJdkRoot(jdkRoot);
      if (info != null) return info;
    }

    return null;
  }

  static Future<String?> findJpackage() async {
    final info = await detect();
    return info?.jpackagePath;
  }

  static JdkInfo? _fromJdkRoot(String root) {
    final jpackage = p.join(root, 'bin', 'jpackage.exe');
    final java = p.join(root, 'bin', 'java.exe');
    final javac = p.join(root, 'bin', 'javac.exe');
    final jdeps = p.join(root, 'bin', 'jdeps.exe');
    final jar = p.join(root, 'bin', 'jar.exe');
    final f = File(jpackage);
    if (!f.existsSync()) return null;
    return JdkInfo(
      jdkPath: root,
      jpackagePath: jpackage,
      javaPath: java,
      javacPath: javac,
      jdepsPath: jdeps,
      jarPath: jar,
    );
  }

  static Future<String?> _lookUpInPath(String tool) async {
    final result = await Process.run('where', [tool]);
    if (result.exitCode != 0) return null;
    final out = (result.stdout as String).trim();
    if (out.isEmpty) return null;
    final lines = out.split(RegExp(r'\r?\n'));
    return lines.firstOrNull;
  }
}

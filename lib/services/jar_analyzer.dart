import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../models/jar_info.dart';

class _ByteReader {
  final Uint8List bytes;
  int offset = 0;
  _ByteReader(this.bytes);

  int u1() => bytes[offset++];
  int u2() => (bytes[offset++] << 8) | bytes[offset++];
  int u4() =>
      (bytes[offset++] << 24) |
      (bytes[offset++] << 16) |
      (bytes[offset++] << 8) |
      bytes[offset++];
  void skip(int n) => offset += n;
  Uint8List take(int n) {
    final r = Uint8List.sublistView(bytes, offset, offset + n);
    offset += n;
    return r;
  }
}

class _MethodInfo {
  final int access;
  final int nameIndex;
  final int descIndex;
  _MethodInfo(this.access, this.nameIndex, this.descIndex);
}

class _ClassFile {
  final List<dynamic> cp = [null];
  late int accessFlags;
  late int thisClassIndex;
  late int superClassIndex;
  late List<_MethodInfo> methods;

  void parse(Uint8List bytes) {
    final r = _ByteReader(bytes);
    r.skip(8);
    final cpCount = r.u2();
    for (int i = 1; i < cpCount; i++) {
      final tag = r.u1();
      switch (tag) {
        case 1:
          final len = r.u2();
          cp.add(utf8.decode(r.take(len)));
          break;
        case 3:
        case 4:
          r.skip(4);
          cp.add(null);
          break;
        case 5:
        case 6:
          r.skip(8);
          cp.add(null);
          cp.add(null);
          i++;
          break;
        case 7:
          cp.add({'type': 'Class', 'nameIndex': r.u2()});
          break;
        case 8:
          r.u2();
          cp.add(null);
          break;
        case 9:
        case 10:
        case 11:
          cp.add({'type': 'Ref', 'classIndex': r.u2(), 'natIndex': r.u2()});
          break;
        case 12:
          cp.add({'type': 'NameAndType', 'nameIndex': r.u2(), 'descIndex': r.u2()});
          break;
        case 15:
          r.u1();
          r.u2();
          cp.add(null);
          break;
        case 16:
          r.u2();
          cp.add(null);
          break;
        case 17:
        case 18:
          r.u2();
          r.u2();
          cp.add(null);
          break;
        case 19:
        case 20:
          r.u2();
          cp.add(null);
          break;
        default:
          throw StateError('Unknown constant pool tag: $tag at index $i');
      }
    }
    accessFlags = r.u2();
    thisClassIndex = r.u2();
    superClassIndex = r.u2();
    final ifaces = r.u2();
    r.skip(ifaces * 2);
    final fieldsCount = r.u2();
    for (int i = 0; i < fieldsCount; i++) {
      r.u2();
      r.u2();
      r.u2();
      final ac = r.u2();
      for (int j = 0; j < ac; j++) {
        r.u2();
        final al = r.u4();
        r.skip(al);
      }
    }
    final mCount = r.u2();
    methods = [];
    for (int i = 0; i < mCount; i++) {
      final access = r.u2();
      final nameIndex = r.u2();
      final descIndex = r.u2();
      final ac = r.u2();
      for (int j = 0; j < ac; j++) {
        r.u2();
        final al = r.u4();
        r.skip(al);
      }
      methods.add(_MethodInfo(access, nameIndex, descIndex));
    }
  }

  String? _className(int index) {
    if (index <= 0 || index >= cp.length) return null;
    final e = cp[index];
    if (e is Map && e['type'] == 'Class') {
      final ni = e['nameIndex'] as int;
      if (ni > 0 && ni < cp.length) return cp[ni] as String?;
    }
    return null;
  }

  String? get thisClassName => _className(thisClassIndex);
  String? get superClassName => _className(superClassIndex);

  bool get hasMainMethod {
    const accPublic = 0x0001;
    const accStatic = 0x0008;
    for (final m in methods) {
      final name = cp[m.nameIndex];
      final desc = cp[m.descIndex];
      if (name == 'main' &&
          desc == '([Ljava/lang/String;)V' &&
          (m.access & (accPublic | accStatic)) == (accPublic | accStatic)) {
        return true;
      }
    }
    return false;
  }
}

class JarAnalyzer {
  static const _fxApplicationInternal = 'javafx/application/Application';

  Future<JarInfo> analyze(String jarPath) async {
    final bytes = await File(jarPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    String? manifestMain;
    bool isModular = false;
    final classData = <Uint8List>[];

    for (final file in archive) {
      final name = file.name;
      if (name == 'META-INF/MANIFEST.MF') {
        manifestMain = _parseManifestMainClass(
          String.fromCharCodes(file.content as List<int>),
        );
      } else if (name == 'module-info.class') {
        isModular = true;
      }
    }

    for (final file in archive) {
      if (file.name.endsWith('.class') && file.name != 'module-info.class') {
        classData.add(Uint8List.fromList(file.content as List<int>));
      }
    }

    final candidates = <MainClassEntry>[];
    final seen = <String>{};
    bool needsJavaFx = false;
    for (final data in classData) {
      try {
        final cf = _ClassFile()..parse(data);
        final internal = cf.thisClassName;
        if (internal == null) continue;
        final className = internal.replaceAll('/', '.');
        if (seen.contains(className)) continue;
        final isFxApp = cf.superClassName == _fxApplicationInternal;
        final hasMain = cf.hasMainMethod;
        if (isFxApp) needsJavaFx = true;
        if (cf.superClassName != null && cf.superClassName!.startsWith('javafx/')) {
          needsJavaFx = true;
        }
        if (hasMain || isFxApp) {
          seen.add(className);
          candidates.add(MainClassEntry(
            className: className,
            type: isFxApp
                ? MainClassType.javafxApplication
                : (className == manifestMain
                    ? MainClassType.manifest
                    : MainClassType.mainMethod),
          ));
        }
      } catch (_) {
        continue;
      }
    }

    candidates.sort((a, b) {
      if (a.className == manifestMain && b.className != manifestMain) return -1;
      if (b.className == manifestMain && a.className != manifestMain) return 1;
      return a.className.compareTo(b.className);
    });

    return JarInfo(
      path: jarPath,
      moduleName: _deriveModuleName(jarPath),
      manifestMainClass: manifestMain,
      candidateEntries: candidates,
      isModular: isModular,
      needsJavaFxSdk: needsJavaFx,
    );
  }

  String _deriveModuleName(String jarPath) {
    final base = jarPath.split(RegExp(r'[/\\]')).last;
    final name = base.endsWith('.jar') ? base.substring(0, base.length - 4) : base;
    final sb = StringBuffer();
    bool prevSep = false;
    for (int i = 0; i < name.length; i++) {
      final c = name[i];
      if (c == '-' || c == '_' || c == '.') {
        if (!prevSep && sb.isNotEmpty) sb.write('.');
        prevSep = true;
      } else if (_isValidModuleChar(c)) {
        sb.write(c.toLowerCase());
        prevSep = false;
      } else {
        if (!prevSep && sb.isNotEmpty) sb.write('_');
        prevSep = true;
      }
    }
    final result = sb.toString().replaceAll(RegExp(r'\.{2,}'), '.');
    return result.isEmpty ? 'app' : result;
  }

  bool _isValidModuleChar(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A);
  }

  String? _parseManifestMainClass(String manifest) {
    for (final line in manifest.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('Main-Class:')) {
        return trimmed.substring('Main-Class:'.length).trim();
      }
    }
    return null;
  }
}

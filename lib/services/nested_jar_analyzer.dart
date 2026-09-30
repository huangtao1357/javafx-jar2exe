import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'log_types.dart';

/// 分析 fat jar 内**嵌套的 jar** 所依赖的 JDK 模块。
///
/// 背景：不少 fat jar（尤其自带 Launcher 的打包方式）会把依赖 jar 原样塞进
/// `lib/*.jar` 而不是展开 class。`jdeps <jar>` 只分析顶层 class，嵌套 jar 里的
/// 依赖完全不可见，于是 okhttp/okio/jfoenix 这类库对 `java.logging` 的需求被漏掉，
/// `--add-modules` 凑不齐 → 运行期 `NoClassDefFoundError: java/util/logging/Logger`。
///
/// 这里把嵌套 jar 释放到临时目录后逐个跑 `jdeps --list-deps`，取并集。
class NestedJarAnalyzer {
  /// 返回嵌套 jar 依赖的模块名（已排除 java.base）。失败时返回空集合，
  /// 调用方据此保持原有行为，不因分析失败而阻塞打包。
  Future<Set<String>> analyze({
    required String jarPath,
    required String jdkPath,
    required LogSink log,
  }) async {
    final jdeps = p.join(jdkPath, 'bin', 'jdeps.exe');
    if (!File(jdeps).existsSync()) {
      log('[Nested] 未找到 jdeps，跳过嵌套 jar 分析', LogLevel.warning);
      return {};
    }

    final nested = await _extractNestedJars(jarPath, log);
    if (nested.isEmpty) return {};

    log('[Nested] 在 jar 内发现 ${nested.length} 个嵌套 jar，开始分析其模块依赖',
        LogLevel.info);

    final modules = <String>{};
    final tmpRoot = Directory(nested.first).parent;
    try {
      for (final path in nested) {
        final name = p.basename(path);
        try {
          final result = await Process.run(
            jdeps,
            ['--list-deps', '--ignore-missing-deps', path],
            stdoutEncoding: const Utf8Codec(allowMalformed: true),
            stderrEncoding: const Utf8Codec(allowMalformed: true),
          ).timeout(const Duration(seconds: 60));
          if (result.exitCode != 0) {
            log('[Nested] $name 分析失败（退出码 ${result.exitCode}），跳过', LogLevel.warning);
            continue;
          }
          final found = _parseListDeps(result.stdout as String);
          if (found.isNotEmpty) {
            log('[Nested] $name -> ${found.join(', ')}', LogLevel.info);
          }
          modules.addAll(found);
        } catch (e) {
          log('[Nested] $name 分析异常，跳过: $e', LogLevel.warning);
        }
      }
    } finally {
      try {
        await tmpRoot.delete(recursive: true);
      } catch (_) {}
    }

    return modules;
  }

  /// 展开 jar，把所有 `.jar` 条目释放到临时目录并返回其路径。
  Future<List<String>> _extractNestedJars(String jarPath, LogSink log) async {
    Directory? workDir;
    try {
      final bytes = await File(jarPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final nested = archive.files
          .where((f) => f.isFile && f.name.toLowerCase().endsWith('.jar'))
          .toList();
      if (nested.isEmpty) return [];

      final tmp = await getTemporaryDirectory();
      workDir = Directory(p.join(
        tmp.path,
        'jpackage_gui_nested_${DateTime.now().millisecondsSinceEpoch}',
      ));
      await workDir.create(recursive: true);

      final out = <String>[];
      for (final f in nested) {
        // 取扁平文件名，避免 lib/ 之类的目录结构干扰
        final target = p.join(workDir.path, p.basename(f.name));
        await File(target).writeAsBytes(f.content as List<int>, flush: true);
        out.add(target);
      }
      return out;
    } catch (e) {
      log('[Nested] 展开嵌套 jar 失败，跳过: $e', LogLevel.warning);
      if (workDir != null) {
        try {
          await workDir.delete(recursive: true);
        } catch (_) {}
      }
      return [];
    }
  }

  /// 解析 `jdeps --list-deps` 输出：每行形如 "   java.logging"，含警告行需过滤。
  Set<String> _parseListDeps(String stdout) {
    final result = <String>{};
    for (final raw in const LineSplitter().convert(stdout)) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      // 模块名仅含字母/数字/点/下划线；以此排除 "Warning:" 等诊断行
      if (!RegExp(r'^[A-Za-z_][\w.]*$').hasMatch(t)) continue;
      if (t == 'java.base') continue;
      result.add(t);
    }
    return result;
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/pack_config.dart';

class ConfigStorage {
  static const _fileName = 'pack_config.json';

  Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<PackConfig?> load() async {
    try {
      final file = await _configFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PackConfig.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PackConfig config) async {
    try {
      final file = await _configFile();
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(config.toJson()));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final file = await _configFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

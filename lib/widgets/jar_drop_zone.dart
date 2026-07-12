import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/pack_viewmodel.dart';

class JarDropZone extends StatelessWidget {
  const JarDropZone({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PackViewModel>();
    final hasJar = vm.config.jarPath.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 90,
          decoration: BoxDecoration(
            color: hasJar ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasJar ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
              width: 1.5,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: vm.isPacking ? null : () => _pickJar(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: hasJar ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 22,
                      color: hasJar ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasJar ? '已选择 jar 文件' : '拖拽 .jar 文件到此处',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: hasJar ? const Color(0xFF1E40AF) : const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasJar ? vm.config.jarPath : '或点击此区域选择文件',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasJar ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!hasJar)
                    const Icon(Icons.touch_app, size: 16, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          ),
        ),
        if (vm.jarInfo != null) ...[
          const SizedBox(height: 8),
          _JarInfoSummary(jarInfo: vm.jarInfo!),
        ],
      ],
    );
  }

  Future<void> _pickJar(BuildContext context) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jar'],
    );
    final path = res?.files.firstOrNull?.path;
    if (path != null && context.mounted) {
      await context.read<PackViewModel>().selectJar(path);
    }
  }
}

class _JarInfoSummary extends StatelessWidget {
  final dynamic jarInfo;
  const _JarInfoSummary({required this.jarInfo});

  @override
  Widget build(BuildContext context) {
    final ji = jarInfo;
    final main = ji.defaultEntry;
    final entries = ji.candidateEntries as List;
    final isModular = ji.isModular as bool;
    final manifest = ji.manifestMainClass;
    final needsFx = ji.needsJavaFxSdk as bool;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, size: 14, color: Color(0xFF0EA5E9)),
              const SizedBox(width: 4),
              const Text(
                '已解析',
                style: TextStyle(fontSize: 12, color: Color(0xFF0369A1), fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              _tag(isModular ? '模块化' : '非模块化', isModular ? const Color(0xFF16A34A) : const Color(0xFFEA580C)),
              if (needsFx) ...[
                const SizedBox(width: 4),
                _tag('JavaFX', const Color(0xFF7C3AED)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _kv('模块名', ji.moduleName as String),
          if (manifest != null) _kv('Manifest Main-Class', manifest),
          _kv('默认入口', main?.label ?? '(无)'),
          if (entries.length > 1) ...[
            const SizedBox(height: 4),
            Text(
              '共扫描到 ${entries.length} 个候选入口类',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text('$k:', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 11, color: Color(0xFF334155)))),
          ],
        ),
      );
}

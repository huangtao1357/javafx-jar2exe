import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
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
            color: hasJar
                ? AppPalette.primary.withValues(alpha: 0.07)
                : AppPalette.surfaceSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasJar
                  ? AppPalette.primary
                  : AppPalette.border,
              width: 1.5,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: vm.isPacking ? null : () => _pickJar(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: hasJar
                          ? const LinearGradient(
                              colors: [AppPalette.primaryLight, AppPalette.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: hasJar ? null : AppPalette.border,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 22,
                      color: hasJar ? Colors.white : Colors.grey.shade500,
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
                            color: hasJar
                                ? AppPalette.primaryDark
                                : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasJar ? vm.config.jarPath : '或点击此区域选择文件',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasJar
                                ? Colors.grey.shade600
                                : Colors.grey.shade400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!hasJar)
                    Icon(Icons.touch_app, size: 16, color: Colors.grey.shade400),
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
    final bundlesFx = ji.bundlesJavaFx as bool;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppPalette.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, size: 14, color: AppPalette.primary),
              const SizedBox(width: 4),
              const Text(
                '已解析',
                style: TextStyle(fontSize: 12, color: AppPalette.primaryDark, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              _tag(isModular ? '模块化' : '非模块化', isModular ? const Color(0xFF16A34A) : const Color(0xFFEA580C)),
              if (needsFx) ...[
                const SizedBox(width: 4),
                _tag('JavaFX', const Color(0xFF7C3AED)),
              ],
              if (bundlesFx) ...[
                const SizedBox(width: 4),
                _tag('内置JavaFX', const Color(0xFF0D9488)),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../viewmodels/pack_viewmodel.dart';

class ActionBar extends StatelessWidget {
  const ActionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PackViewModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: GradientButton(
                onPressed: vm.isPacking ? null : vm.startPack,
                icon: const Icon(Icons.play_arrow),
                label: '开始打包',
              ),
            ),
            if (vm.isPacking) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.dangerDeep,
                  side: BorderSide(color: AppPalette.danger.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                ),
                onPressed: vm.cancelPack,
                icon: const Icon(Icons.stop, size: 20),
                label: const Text('取消', style: TextStyle(fontSize: 13.5)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: vm.lastOutputExe == null ? null : vm.openOutputDir,
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('打开输出目录', style: TextStyle(fontSize: 13)),
        ),
        if (vm.lastOutputExe != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppPalette.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppPalette.success.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppPalette.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '打包成功！\n${vm.lastOutputExe}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppPalette.successDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

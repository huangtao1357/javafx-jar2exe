import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                onPressed: vm.isPacking ? null : vm.startPack,
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('开始打包', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ),
            if (vm.isPacking) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: const BorderSide(color: Color(0xFFFECACA)),
                ),
                onPressed: vm.cancelPack,
                icon: const Icon(Icons.stop, size: 20),
                label: const Text('取消'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF475569),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                onPressed: vm.lastOutputExe == null ? null : vm.openOutputDir,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('打开输出目录', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
        if (vm.lastOutputExe != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '打包成功！\n${vm.lastOutputExe}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF15803D)),
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

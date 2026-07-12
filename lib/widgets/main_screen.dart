import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/pack_viewmodel.dart';
import 'action_bar.dart';
import 'jar_drop_zone.dart';
import 'log_console.dart';
import 'param_form.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.inventory_2, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'JPackage GUI',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'JavaFX jar → Windows exe',
                style: TextStyle(fontSize: 11, color: Color(0xFF2563EB)),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '重置配置',
            icon: const Icon(Icons.restart_alt, size: 20),
            onPressed: () => context.read<PackViewModel>().resetConfig(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: const _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PackViewModel>();
    final theme = Theme.of(context);
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        if (vm.isPacking) return;
        for (final f in detail.files) {
          final path = f.path;
          if (path.toLowerCase().endsWith('.jar')) {
            vm.selectJar(path);
            break;
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          border: _dragging
              ? Border.all(color: theme.colorScheme.primary, width: 3)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧：表单区（约 58%）
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 6, 12),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const JarDropZone(),
                        const SizedBox(height: 16),
                        const ParamForm(),
                        const SizedBox(height: 16),
                        const ActionBar(),
                        if (vm.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    vm.errorMessage!,
                                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 右侧：日志区（约 42%）
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.fromLTRB(6, 12, 12, 12),
                child: const LogConsole(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

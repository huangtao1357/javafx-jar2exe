import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/log_types.dart';
import '../theme/app_theme.dart';
import '../viewmodels/pack_viewmodel.dart' show LogEntry, PackViewModel;

class LogConsole extends StatefulWidget {
  const LogConsole({super.key});

  @override
  State<LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends State<LogConsole> {
  final ScrollController _scroll = ScrollController();
  bool _userScrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final atBottom = _scroll.position.maxScrollExtent - _scroll.offset < 40;
      if (!atBottom != _userScrolled) {
        setState(() => _userScrolled = !atBottom);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PackViewModel>();
    final entries = vm.logEntries;
    if (vm.autoScroll && !_userScrolled) {
      _scrollToBottom();
    }

    return AppCard(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.terminal, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          '点击「开始打包」后，详细日志将在此处实时显示',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : SelectionArea(
                    child: Container(
                      color: AppPalette.surface,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        itemCount: entries.length,
                        itemBuilder: (_, i) => _LogLine(entry: entries[i]),
                      ),
                    ),
                  ),
          ),
          if (vm.isPacking)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: AppPalette.border,
              valueColor: const AlwaysStoppedAnimation(AppPalette.primary),
            ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PackViewModel>();
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.list_alt, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          const Text(
            '构建日志',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          if (vm.isPacking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppPalette.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                  ),
                  SizedBox(width: 4),
                  Text('运行中', style: TextStyle(fontSize: 10, color: Colors.white)),
                ],
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: vm.autoScroll ? '已跟随滚动' : '已暂停滚动',
            iconSize: 16,
            icon: Icon(
              vm.autoScroll ? Icons.vertical_align_bottom : Icons.pause_circle_outline,
              color: vm.autoScroll ? AppPalette.primary : Colors.grey.shade400,
            ),
            onPressed: vm.isPacking
                ? null
                : () => vm.setAutoScroll(!vm.autoScroll),
          ),
          IconButton(
            tooltip: '清空日志',
            iconSize: 16,
            icon: Icon(Icons.delete_outline, color: Colors.grey.shade400),
            onPressed: vm.isPacking ? null : vm.clearLogs,
          ),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final LogEntry entry;
  const _LogLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final (color, bgColor) = switch (entry.level) {
      LogLevel.command => (Colors.grey.shade600, AppPalette.surfaceSoft),
      LogLevel.info => (const Color(0xFF2E2F44), Colors.transparent),
      LogLevel.success => (AppPalette.successDeep, AppPalette.success.withValues(alpha: 0.08)),
      LogLevel.warning => (AppPalette.warningDeep, AppPalette.warning.withValues(alpha: 0.10)),
      LogLevel.error => (AppPalette.dangerDeep, AppPalette.danger.withValues(alpha: 0.08)),
    };
    final isCommand = entry.level == LogLevel.command;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        entry.toTextLine(),
        style: TextStyle(
          fontSize: 12,
          fontFamily: 'Consolas',
          color: color,
          fontWeight: isCommand ? FontWeight.w600 : FontWeight.normal,
          height: 1.4,
        ),
      ),
    );
  }
}

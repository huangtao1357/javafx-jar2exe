import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../viewmodels/pack_viewmodel.dart';
import 'about_dialog.dart';
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
        titleSpacing: 16,
        title: const _BrandTitle(),
        actions: const [
          _VersionBadge(),
          _AboutButton(),
          _ResetButton(),
          SizedBox(width: 8),
        ],
      ),
      body: const _Body(),
    );
  }
}

/// 品牌区：渐变发光图标 + 名称 + 标语
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppPalette.primaryLight, AppPalette.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(11),
            boxShadow: AppShadows.glow(AppPalette.primary),
          ),
          child: const Icon(Icons.inventory_2, color: Colors.white, size: 21),
        ),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'JPackage GUI',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            Text(
              'JAVAFX JAR → EXE',
              style: TextStyle(
                fontSize: 9,
                color: AppPalette.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 标题栏版本徽标：点击打开「关于」
class _VersionBadge extends StatefulWidget {
  const _VersionBadge();

  @override
  State<_VersionBadge> createState() => _VersionBadgeState();
}

class _VersionBadgeState extends State<_VersionBadge> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'v${info.version}+${info.buildNumber}');
    } catch (_) {
      // 平台通道不可用时隐藏徽标
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_version.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showAboutAppDialog(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppPalette.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _version,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppPalette.primaryDark,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutButton extends StatelessWidget {
  const _AboutButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '关于',
      icon: const Icon(Icons.info_outline, size: 20),
      onPressed: () => showAboutAppDialog(context),
    );
  }
}

class _ResetButton extends StatelessWidget {
  const _ResetButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '重置配置',
      icon: const Icon(Icons.restart_alt, size: 20),
      onPressed: () => context.read<PackViewModel>().resetConfig(),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppPalette.bgGradTop, AppPalette.bgGradBottom],
          ),
          border: null,
        ),
        foregroundDecoration: _dragging
            ? BoxDecoration(
                border: Border.all(color: AppPalette.primary, width: 3),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧：表单区（约 58%）
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 8, 16),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: AppCard(
                    padding: const EdgeInsets.all(18),
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
                              color: AppPalette.danger.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppPalette.danger.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: AppPalette.dangerDeep, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    vm.errorMessage!,
                                    style: const TextStyle(
                                      color: AppPalette.dangerDeep,
                                      fontSize: 13,
                                    ),
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
                margin: const EdgeInsets.fromLTRB(8, 4, 16, 16),
                child: const LogConsole(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

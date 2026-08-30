import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/jar_info.dart';
import '../theme/app_theme.dart';
import '../viewmodels/pack_viewmodel.dart';

class ParamForm extends StatelessWidget {
  const ParamForm({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PackViewModel>();
    final c = vm.config;
    final disabled = vm.isPacking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle('基础参数'),
        _TextField(
          label: '应用名称 *',
          value: c.appName,
          enabled: !disabled,
          onChanged: (v) => vm.updateConfig((x) => x.appName = v),
        ),
        const SizedBox(height: 8),
        _TextField(
          label: '应用版本号 *',
          value: c.appVersion,
          enabled: !disabled,
          onChanged: (v) => vm.updateConfig((x) => x.appVersion = v),
        ),
        const SizedBox(height: 8),
        _MainClassField(disabled: disabled),
        const SizedBox(height: 8),
        _PathField(
          label: '应用图标 (可选)',
          value: c.iconPath ?? '',
          enabled: !disabled,
          buttonText: '选择 .ico',
          onPick: () async {
            final res = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['ico'],
            );
            return res?.files.firstOrNull?.path;
          },
          onChanged: (v) => vm.updateConfig((x) => x.iconPath = v.isEmpty ? null : v),
        ),
        const SizedBox(height: 8),
        _PathField(
          label: '输出目录 *',
          value: c.outputDir,
          enabled: !disabled,
          buttonText: '选择目录',
          onPick: () async {
            final res = await FilePicker.platform.getDirectoryPath();
            return res;
          },
          onChanged: (v) => vm.updateConfig((x) => x.outputDir = v),
        ),
        const SizedBox(height: 16),
        _SectionTitle('运行时'),
        _PathField(
          label: 'JDK 路径 *',
          value: c.jdkPath,
          enabled: !disabled,
          buttonText: '选择目录',
          onPick: () async {
            final res = await FilePicker.platform.getDirectoryPath();
            return res;
          },
          onChanged: (v) => vm.pickJdkPath(v),
        ),
        const SizedBox(height: 8),
        if (vm.jarInfo?.needsJavaFxSdk == true) ...[
          _PathField(
            label: 'JavaFX SDK 路径 * (检测到 JavaFX 依赖)',
            value: c.javafxSdkPath ?? '',
            enabled: !disabled,
            buttonText: '选择目录',
            onPick: () async {
              final res = await FilePicker.platform.getDirectoryPath();
              return res;
            },
            onChanged: (v) => vm.updateConfig((x) => x.javafxSdkPath = v.isEmpty ? null : v),
          ),
          const SizedBox(height: 8),
          _JavaFxModulesField(
            value: c.javafxModules,
            enabled: !disabled,
            onChanged: (v) => vm.updateConfig((x) => x.javafxModules = v),
          ),
          const SizedBox(height: 4),
          _SwitchRow(
            label: '裁剪未使用的 JavaFX DLL（排除 jfxwebkit.dll 等，省 ~94MB）',
            value: c.stripUnusedJavaFxDlls,
            enabled: !disabled,
            onChanged: (v) => vm.updateConfig((x) => x.stripUnusedJavaFxDlls = v),
          ),
        ],
        const SizedBox(height: 8),
        _TextField(
          label: '供应商 (vendor)',
          value: c.vendor,
          enabled: !disabled,
          onChanged: (v) => vm.updateConfig((x) => x.vendor = v),
        ),
        const SizedBox(height: 8),
        _TextField(
          label: 'Java 运行时参数 (可选)',
          value: c.javaOptions,
          enabled: !disabled,
          hint: r'如 -Xmx512m',
          onChanged: (v) => vm.updateConfig((x) => x.javaOptions = v),
        ),
        const SizedBox(height: 8),
        _TextField(
          label: '应用参数 (可选)',
          value: c.appArguments,
          enabled: !disabled,
          onChanged: (v) => vm.updateConfig((x) => x.appArguments = v),
        ),
        const SizedBox(height: 16),
        _SectionTitle('保护与产物'),
        _SwitchRow(
          label: 'ProGuard 混淆（隐藏类名）',
          value: c.enableProGuard,
          enabled: !disabled,
          onChanged: (v) => vm.updateConfig((x) => x.enableProGuard = v),
        ),
        _SwitchRow(
          label: '保留资源文件名 (fxml/css)',
          value: c.keepResources,
          enabled: !disabled,
          onChanged: (v) => vm.updateConfig((x) => x.keepResources = v),
        ),
        _SwitchRow(
          label: '同时生成 .msi 安装包',
          value: c.generateMsi,
          enabled: !disabled,
          onChanged: (v) => vm.updateConfig((x) => x.generateMsi = v),
        ),
      ],
    );
  }
}

class _JavaFxModulesField extends StatefulWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const _JavaFxModulesField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_JavaFxModulesField> createState() => _JavaFxModulesFieldState();
}

class _JavaFxModulesFieldState extends State<_JavaFxModulesField> {
  static const _allModules = [
    ('javafx.controls', 'controls（按钮、列表等基础控件）'),
    ('javafx.fxml', 'fxml（FXML 布局加载）'),
    ('javafx.graphics', 'graphics（渲染引擎，必需）'),
    ('javafx.web', 'web（WebView 浏览器，+93MB）'),
    ('javafx.media', 'media（音频/视频播放，+1.3MB）'),
    ('javafx.swing', 'swing（Swing 互操作）'),
  ];

  List<String> _selected() => widget.value
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  void _toggle(String mod) {
    final list = _selected();
    if (list.contains(mod)) {
      list.remove(mod);
    } else {
      list.add(mod);
    }
    widget.onChanged(list.join(','));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected();
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
          const Row(
            children: [
              Icon(Icons.extension, size: 14, color: AppPalette.primary),
              SizedBox(width: 4),
              Text(
                'JavaFX 模块选择',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.primaryDark),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (mod, desc) in _allModules)
                FilterChip(
                  label: Text(mod, style: const TextStyle(fontSize: 11)),
                  tooltip: desc,
                  selected: selected.contains(mod),
                  onSelected: widget.enabled ? (_) => _toggle(mod) : null,
                  selectedColor: AppPalette.primary,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    color: selected.contains(mod) ? Colors.white : const Color(0xFF5B5C74),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '勾选 web 会自动包含 jfxwebkit.dll；勾选 media 会自动包含 gstreamer/jfxmedia',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppPalette.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatefulWidget {
  final String label;
  final String value;
  final bool enabled;
  final String? hint;
  final ValueChanged<String> onChanged;
  const _TextField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.hint,
  });

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在外部值变化且与当前输入框内容不同时同步（避免光标跳转）
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      final selection = _controller.selection;
      _controller.text = widget.value;
      // 尝试保持光标位置
      final newOffset = selection.baseOffset.clamp(0, widget.value.length);
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: newOffset));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
      ),
      enabled: widget.enabled,
      onChanged: widget.onChanged,
    );
  }
}

class _PathField extends StatefulWidget {
  final String label;
  final String value;
  final bool enabled;
  final String buttonText;
  final Future<String?> Function() onPick;
  final ValueChanged<String> onChanged;
  const _PathField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.buttonText,
    required this.onPick,
    required this.onChanged,
  });

  @override
  State<_PathField> createState() => _PathFieldState();
}

class _PathFieldState extends State<_PathField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_PathField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(labelText: widget.label),
            enabled: widget.enabled,
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onPressed: widget.enabled
              ? () async {
                  final p = await widget.onPick();
                  if (p != null) widget.onChanged(p);
                }
              : null,
          child: Text(widget.buttonText, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

class _MainClassField extends StatefulWidget {
  final bool disabled;
  const _MainClassField({required this.disabled});

  @override
  State<_MainClassField> createState() => _MainClassFieldState();
}

class _MainClassFieldState extends State<_MainClassField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _showOptions = false;
  String? _lastMainClass;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _select(String className, PackViewModel vm) {
    _controller.text = className;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: className.length),
    );
    vm.updateConfig((x) => x.mainClass = className);
    setState(() => _showOptions = false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PackViewModel>();
    final candidates = vm.jarInfo?.selectableEntries ?? [];
    final currentMain = vm.config.mainClass;

    // 同步外部变更（如选择新 jar 时 applyJarInfo 更新了 mainClass）
    if (currentMain != _lastMainClass && currentMain != _controller.text) {
      _controller.text = currentMain;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: currentMain.length),
      );
    }
    _lastMainClass = currentMain;

    final filteredOptions = candidates
        .where((e) => e.className.toLowerCase().contains(_controller.text.toLowerCase()))
        .where((e) => e.className != _controller.text)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Main-Class *', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: !widget.disabled,
          decoration: InputDecoration(
            hintText: '选择或输入完整类名',
            suffixIcon: candidates.isEmpty
                ? null
                : const Icon(Icons.arrow_drop_down, size: 18),
          ),
          onTap: () {
            if (candidates.isNotEmpty) setState(() => _showOptions = true);
          },
          onChanged: (v) {
            vm.updateConfig((x) => x.mainClass = v);
            if (candidates.isNotEmpty) setState(() => _showOptions = true);
          },
          onSubmitted: (_) => setState(() => _showOptions = false),
        ),
        // 下拉选项列表
        if (_showOptions && filteredOptions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppPalette.border),
              borderRadius: BorderRadius.circular(10),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in filteredOptions.take(8))
                  InkWell(
                    onTap: widget.disabled ? null : () => _select(e.className, vm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            e.type == MainClassType.javafxApplication
                                ? Icons.window
                                : Icons.code,
                            size: 14,
                            color: const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(e.className, style: const TextStyle(fontSize: 12))),
                          if (e.className == currentMain)
                            const Icon(Icons.check, size: 14, color: AppPalette.primary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in candidates.take(6))
                GestureDetector(
                  onTap: widget.disabled ? null : () => _select(e.className, vm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: e.className == currentMain
                          ? AppPalette.primary
                          : AppPalette.surfaceSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: e.className == currentMain
                            ? AppPalette.primary
                            : AppPalette.border,
                      ),
                    ),
                    child: Text(
                      e.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: e.className == currentMain
                            ? Colors.white
                            : const Color(0xFF5B5C74),
                        fontWeight: e.className == currentMain ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value
              ? AppPalette.primary.withValues(alpha: 0.07)
              : AppPalette.surfaceSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: value ? AppPalette.primaryDark : const Color(0xFF5B5C74),
                  fontWeight: value ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            Switch(value: value, onChanged: enabled ? onChanged : null),
          ],
        ),
      ),
    );
  }
}

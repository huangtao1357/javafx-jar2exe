import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/jar_info.dart';
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
        if (vm.jarInfo?.needsJavaFxSdk == true)
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
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: value)..selection = TextSelection.fromPosition(TextPosition(offset: value.length)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
      ),
      enabled: enabled,
      onChanged: onChanged,
    );
  }
}

class _PathField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(text: value)
              ..selection = TextSelection.fromPosition(TextPosition(offset: value.length)),
            decoration: InputDecoration(labelText: label),
            enabled: enabled,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF2563EB),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: const BorderSide(color: Color(0xFF93C5FD)),
            backgroundColor: const Color(0xFFEFF6FF),
          ),
          onPressed: enabled
              ? () async {
                  final p = await onPick();
                  if (p != null) onChanged(p);
                }
              : null,
          child: Text(buttonText, style: const TextStyle(fontSize: 12)),
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
              border: Border.all(color: const Color(0xFFCBD5E1)),
              borderRadius: BorderRadius.circular(8),
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
                            const Icon(Icons.check, size: 14, color: Color(0xFF2563EB)),
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
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: e.className == currentMain
                            ? const Color(0xFF2563EB)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Text(
                      e.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: e.className == currentMain
                            ? Colors.white
                            : const Color(0xFF475569),
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
          color: value ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: value ? const Color(0xFF1E40AF) : const Color(0xFF475569),
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

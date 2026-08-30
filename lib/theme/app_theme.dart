import 'package:flutter/material.dart';

/// 应用主题色板 —— 淡雅靛蓝 · 薰衣草（与 apkjiagu 同一设计语言）
/// 主色 indigo (#6366F1) + 辅色 lavender (#A78BFA)
class AppPalette {
  // 主色阶
  static const primary = Color(0xFF6366F1); // indigo-500
  static const primaryDark = Color(0xFF4F46E5); // indigo-600（渐变尾 / 按压）
  static const primaryLight = Color(0xFF818CF8); // indigo-400（渐变头）

  // 辅色阶
  static const accent = Color(0xFFA78BFA); // violet-400 lavender

  // 浅色令牌
  static const bgLight = Color(0xFFF6F7FE); // 微紫白背景
  static const bgGradTop = Color(0xFFF8F9FF);
  static const bgGradBottom = Color(0xFFF1F2FC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFF4F5FD); // 输入 / 内嵌区域填充
  static const border = Color(0xFFECEDF8); // 极淡发丝线

  // 语义色
  static const success = Color(0xFF10B981);
  static const successDeep = Color(0xFF047857);
  static const warning = Color(0xFFF59E0B);
  static const warningDeep = Color(0xFFB45309);
  static const danger = Color(0xFFEF4444);
  static const dangerDeep = Color(0xFFDC2626);
}

/// 柔和多层投影 —— 让卡片"浮"起来，营造轻盈感
class AppShadows {
  /// 浅色卡片：一层贴地 + 一层扩散的靛蓝柔影
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0D312E81), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(
      color: Color(0x14312E81),
      blurRadius: 24,
      spreadRadius: -6,
      offset: Offset(0, 12),
    ),
  ];

  /// 主色发光投影：用于主 CTA 按钮 / 品牌图标
  static List<BoxShadow> glow(Color c) => [
        BoxShadow(
          color: c.withValues(alpha: 0.35),
          blurRadius: 18,
          spreadRadius: -4,
          offset: const Offset(0, 8),
        ),
      ];
}

/// 通用「软投影卡片」—— 替代生硬 1px 边框的浮动卡片
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double radius;
  final Clip clipBehavior;
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.radius = 18,
    this.clipBehavior = Clip.none,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: color ?? AppPalette.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }
}

/// 渐变主按钮 —— 用于关键 CTA（如「开始打包」）
class GradientButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  const GradientButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled
            ? const LinearGradient(
                colors: [AppPalette.primaryLight, AppPalette.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: enabled ? null : AppPalette.primary.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        boxShadow: enabled ? AppShadows.glow(AppPalette.primary) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: const IconThemeData(color: Colors.white, size: 19),
                  child: icon,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 应用主题（浅色）
ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppPalette.primary,
    secondary: AppPalette.accent,
    surface: AppPalette.surface,
  );
  const border = AppPalette.border;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppPalette.bgLight,
    dividerColor: border,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    fontFamily: 'Microsoft YaHei UI',
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
    ),
    textTheme: const TextTheme(
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppPalette.primary,
        side: BorderSide(
          color: AppPalette.primary.withValues(alpha: 0.35),
          width: 1.2,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppPalette.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return const Color(0xFFCBCDE6);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppPalette.primary;
        return const Color(0xFFE6E7F4);
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      showCheckmark: false,
      selectedColor: AppPalette.primary.withValues(alpha: 0.14),
      backgroundColor: AppPalette.surfaceSoft,
      side: BorderSide.none,
      labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppPalette.primaryDark,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppPalette.surfaceSoft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppPalette.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      labelStyle: const TextStyle(color: Color(0xFF5B5C74), fontSize: 13),
      hintStyle: const TextStyle(color: Color(0xFFA9ABC4), fontSize: 12.5),
    ),
  );
}

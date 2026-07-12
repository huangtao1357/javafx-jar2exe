import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'viewmodels/pack_viewmodel.dart';
import 'widgets/main_screen.dart';

void main() {
  runApp(const JPackageGuiApp());
}

class JPackageGuiApp extends StatelessWidget {
  const JPackageGuiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PackViewModel()..init(),
      child: MaterialApp(
        title: 'JPackage GUI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
            brightness: Brightness.light,
          ),
          fontFamily: 'Microsoft YaHei',
          scaffoldBackgroundColor: const Color(0xFFF1F5F9),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          cardTheme: CardThemeData(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
            color: Colors.white,
          ),
          dividerTheme: const DividerThemeData(
            color: Color(0xFFE2E8F0),
            thickness: 1,
            space: 1,
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return Colors.white;
              return const Color(0xFF94A3B8);
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return const Color(0xFF2563EB);
              return const Color(0xFFCBD5E1);
            }),
          ),
        ),
        home: const MainScreen(),
      ),
    );
  }
}

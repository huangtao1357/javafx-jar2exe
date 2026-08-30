import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
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
        theme: buildAppTheme(),
        home: const MainScreen(),
      ),
    );
  }
}

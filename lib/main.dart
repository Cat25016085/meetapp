import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

// 全域的主題控制器
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, _) { // 修正：移除多餘的底線
        return MaterialApp(
          title: '會議簽到投票系統',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            primarySwatch: Colors.indigo,
            useMaterial3: true,
            brightness: Brightness.light,
            // 修正：移除顯式 CardTheme 避免新版 SDK 型別衝突，使用預設即可
          ),
          darkTheme: ThemeData(
            primarySwatch: Colors.indigo,
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1F1F1F)),
            // 修正：移除顯式 CardTheme 避免新版 SDK 型別衝突
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}
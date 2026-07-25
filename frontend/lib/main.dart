import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/download_provider.dart';
import 'providers/library_provider.dart';
import 'providers/player_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/search_provider.dart';
import 'providers/server_provider.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => DownloadProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
      ],
      child: const YtMp3App(),
    ),
  );
}

class YtMp3App extends StatelessWidget {
  const YtMp3App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YT-MP3',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const MainShell(),
    );
  }

  ThemeData _buildTheme() {
    const bg       = Color(0xFF0D0D1A);
    const surface  = Color(0xFF1A1A2E);
    const card     = Color(0xFF16213E);
    const accent   = Color(0xFF6C63FF);
    const onAccent = Color(0xFFFFFFFF);
    const textPri  = Color(0xFFF0F0FF);
    const textSec  = Color(0xFF9090B0);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        background: bg,
        surface: surface,
        primary: accent,
        onPrimary: onAccent,
        secondary: Color(0xFF03DAC6),
        onBackground: textPri,
        onSurface: textPri,
      ),
      cardTheme: const CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textSec),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: textPri, fontSize: 22, fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          color: textPri, fontSize: 15, fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: textSec, fontSize: 13),
        labelSmall: TextStyle(
          color: textSec, fontSize: 11, letterSpacing: 0.5,
        ),
      ),
      iconTheme: const IconThemeData(color: textSec),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A2A40), thickness: 1,
      ),
    );
  }
}

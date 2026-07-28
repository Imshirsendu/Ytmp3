import 'package:flutter/material.dart';

import 'download_screen.dart';
import 'library_screen.dart';
import 'search_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  static const _screens = [
    SearchScreen(),
    DownloadScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Snackbars float above the MiniPlayer (64 px) + nav bar.
    // We achieve this by overriding the snackBarTheme margin on the
    // ScaffoldMessenger level via a local Theme extension.
    //
    // MiniPlayer height = 64, NavigationBar ≈ 80 (safe area included).
    // We add 72 bottom margin so snackbars never hide behind either.
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        snackBarTheme: base.snackBarTheme.copyWith(
          behavior: SnackBarBehavior.floating,
          // 64 (mini player) + 8 gap
          insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 72),
        ),
      ),
      child: Scaffold(
        body: IndexedStack(index: _tab, children: _screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          backgroundColor: Theme.of(context).colorScheme.surface,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search_rounded),
              label: 'Search',
            ),
            NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download),
              label: 'Download',
            ),
            NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music),
              label: 'Library',
            ),
          ],
        ),
      ),
    );
  }
}

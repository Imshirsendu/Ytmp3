import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
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
  bool _resumeChecked = false;

  static const _screens = [
    SearchScreen(),
    DownloadScreen(),
    LibraryScreen(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_resumeChecked) {
      _resumeChecked = true;
      _checkResume();
    }
  }

  Future<void> _checkResume() async {
    final session = await PlayerProvider.loadLastSession();
    if (session == null || !mounted) return;

    // Look up the Track from the library by filePath.
    final lib   = context.read<LibraryProvider>();
    final match = lib.tracks.where((t) => t.filePath == session.filePath);
    if (match.isEmpty || !mounted) return;
    final track = match.first;

    // Show a resume snackbar with an action button.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Resume where you left off?',
                style: TextStyle(fontWeight: FontWeight.w600)),
            Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Resume',
          onPressed: () {
            if (!mounted) return;
            context.read<PlayerProvider>().resumeSession(session, track);
          },
        ),
      ),
    );
  }

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
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              title: const Text('Exit app?'),
              content: const Text('Are you sure you want to exit?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('No'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    'Yes',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );
          if (shouldExit == true && context.mounted) {
            Navigator.of(context).pop();
          }
        },
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
      ),
    );
  }
}
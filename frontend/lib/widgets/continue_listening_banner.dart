import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/player_provider.dart';

/// Drop this widget at the top of any screen (library, home, etc.).
/// It self-loads the last session from shared_preferences and dismisses
/// itself after the user resumes or taps ✕.
///
/// Usage:
///   Column(children: [
///     const ContinueListeningBanner(),
///     ...rest of screen
///   ])
class ContinueListeningBanner extends StatefulWidget {
  /// Provide this if you have access to your full track list so the banner
  /// can find the Track object by filePath. If null the banner won't show.
  final List<Track> Function()? trackSource;

  const ContinueListeningBanner({super.key, this.trackSource});

  @override
  State<ContinueListeningBanner> createState() =>
      _ContinueListeningBannerState();
}

class _ContinueListeningBannerState extends State<ContinueListeningBanner> {
  LastSession? _session;
  Track?       _track;
  bool         _dismissed = false;
  bool         _resuming  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await PlayerProvider.loadLastSession();
    if (session == null || !mounted) return;

    // Try to match the saved filePath against available tracks
    final tracks = widget.trackSource?.call() ?? [];
    final match  = tracks.cast<Track?>().firstWhere(
          (t) => t?.filePath == session.filePath,
          orElse: () => null,
        );

    if (match == null) {
      // File no longer exists — clear stale session silently
      await PlayerProvider.clearLastSession();
      return;
    }

    if (!mounted) return;
    setState(() {
      _session = session;
      _track   = match;
    });
  }

  Future<void> _resume() async {
    final session = _session;
    final track   = _track;
    if (session == null || track == null) return;
    setState(() => _resuming = true);
    await context.read<PlayerProvider>().resumeSession(session, track);
    if (mounted) setState(() => _dismissed = true);
  }

  void _dismiss() {
    PlayerProvider.clearLastSession();
    setState(() => _dismissed = true);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _session == null || _track == null) {
      return const SizedBox.shrink();
    }

    final cs      = Theme.of(context).colorScheme;
    final tt      = Theme.of(context).textTheme;
    final session = _session!;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        decoration: BoxDecoration(
          color: cs.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(Icons.history_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Continue listening',
                        style: tt.labelSmall
                            ?.copyWith(color: cs.primary, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(session.title,
                        style: tt.titleMedium?.copyWith(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      '${session.artist} · ${_fmt(session.position)}',
                      style: tt.bodyMedium?.copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _resuming
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : FilledButton.icon(
                    onPressed: _resume,
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Resume'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
            IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 18, color: cs.onSurface.withOpacity(0.4)),
              onPressed: _dismiss,
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../screens/player_screen.dart';
import '../widgets/cover_art.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (ctx, player, _) {
        final now = player.current;
        if (now == null) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;

        return GestureDetector(
          onTap: () => PlayerScreen.show(context),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF16213E),
              border: Border(
                top: BorderSide(
                    color: cs.onSurface.withOpacity(0.08), width: 1),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),

                // Cover art — network image for streams, embedded bytes for local
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: now.isStream
                        ? (now.stream!.thumbnailUrl != null
                            ? CachedNetworkImage(
                                imageUrl: now.stream!.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    _fallback(cs),
                              )
                            : _fallback(cs))
                        : CoverArt(
                            coverArtBytes: now.local!.coverArt,
                            size: 44),
                  ),
                ),

                const SizedBox(width: 12),

                // Title + artist
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(now.title,
                          style: tt.titleMedium?.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(now.artist,
                          style:
                              tt.bodyMedium?.copyWith(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),

                // Sleep timer indicator
                if (player.sleepTimerActive)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _SleepIndicator(remaining: player.sleepRemaining),
                  ),

                // Play/pause
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  builder: (ctx, snap) {
                    final isPlaying = snap.data?.playing ?? false;
                    return IconButton(
                      iconSize: 28,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: cs.onSurface,
                      ),
                      onPressed: player.togglePlayPause,
                    );
                  },
                ),

                // Next (only for local queue)
                if (!now.isStream)
                  IconButton(
                    iconSize: 24,
                    icon: Icon(Icons.skip_next_rounded,
                        color: player.hasNext
                            ? cs.onSurface
                            : cs.onSurface.withOpacity(0.3)),
                    onPressed: player.hasNext ? player.skipNext : null,
                  ),

                const SizedBox(width: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fallback(ColorScheme cs) => Container(
        color: cs.surface,
        child: Icon(Icons.music_note_rounded,
            size: 22, color: cs.onSurface.withOpacity(0.3)),
      );
}

// ── Sleep timer countdown chip ────────────────────────────────────────────────

class _SleepIndicator extends StatelessWidget {
  final Duration? remaining;
  const _SleepIndicator({this.remaining});

  String get _label {
    final r = remaining;
    if (r == null) return '🌙';
    final m = r.inMinutes.remainder(60);
    final s = r.inSeconds.remainder(60);
    return r.inHours > 0
        ? '🌙 ${r.inHours}h${m}m'
        : m > 0
            ? '🌙 ${m}m'
            : '🌙 ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withOpacity(0.3)),
      ),
      child: Text(
        _label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: cs.primary, fontSize: 10),
      ),
    );
  }
}

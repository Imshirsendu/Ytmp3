import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../screens/queue_screen.dart';
import '../widgets/cover_art.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const PlayerScreen(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(
                  parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('NOW PLAYING',
            style: tt.labelSmall?.copyWith(letterSpacing: 2)),
        centerTitle: true,
        actions: [
          // Queue button — only shown for local queue
          Consumer<PlayerProvider>(
            builder: (ctx, player, _) =>
                player.current?.isStream == false && player.queue.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.queue_music_outlined),
                        tooltip: 'Queue',
                        onPressed: () => QueueScreen.show(context),
                      )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Consumer<PlayerProvider>(
        builder: (ctx, player, _) {
          final now = player.current;
          if (now == null) {
            return const Center(child: Text('Nothing playing'));
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // ── Cover art ──────────────────────────────────────────
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: now.isStream
                          ? _streamCover(now.stream!, cs)
                          : CoverArt(
                              coverArtBytes: now.local!.coverArt,
                              size: double.infinity),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Title & artist ────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(now.title,
                                style: tt.titleMedium
                                    ?.copyWith(fontSize: 18),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(now.artist,
                                    style: tt.bodyMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                if (now.isStream) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.secondary.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('LIVE',
                                        style: tt.labelSmall?.copyWith(
                                            color: cs.secondary,
                                            fontSize: 9,
                                            letterSpacing: 1)),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Seek bar ──────────────────────────────────────────
                  StreamBuilder<Duration>(
                    stream: player.positionStream,
                    builder: (ctx, snap) {
                      final pos = snap.data ?? Duration.zero;
                      final dur = player.duration;
                      final ratio = dur.inMilliseconds > 0
                          ? (pos.inMilliseconds / dur.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0.0;
                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                              activeTrackColor: cs.primary,
                              inactiveTrackColor:
                                  cs.onSurface.withOpacity(0.15),
                              thumbColor: cs.primary,
                              overlayShape:
                                  SliderComponentShape.noOverlay,
                            ),
                            child: Slider(
                              value: ratio,
                              onChanged: (v) => player.seek(Duration(
                                  milliseconds:
                                      (v * dur.inMilliseconds).round())),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmt(pos), style: tt.labelSmall),
                                Text(_fmt(dur), style: tt.labelSmall),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // ── Controls ──────────────────────────────────────────
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (ctx, snap) {
                      final isPlaying = snap.data?.playing ?? false;
                      final isLoading = player.loading ||
                          snap.data?.processingState ==
                              ProcessingState.loading ||
                          snap.data?.processingState ==
                              ProcessingState.buffering;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Previous (hidden for streams)
                          if (!now.isStream)
                            IconButton(
                              iconSize: 36,
                              icon: Icon(Icons.skip_previous_rounded,
                                  color: player.hasPrevious
                                      ? cs.onSurface
                                      : cs.onSurface.withOpacity(0.3)),
                              onPressed: player.hasPrevious
                                  ? player.skipPrevious
                                  : null,
                            ),

                          const SizedBox(width: 16),

                          // Play / Pause
                          GestureDetector(
                            onTap: isLoading
                                ? null
                                : player.togglePlayPause,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                              ),
                              child: isLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(18),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : Icon(
                                      isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 34,
                                      color: cs.onPrimary,
                                    ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Next (hidden for streams)
                          if (!now.isStream)
                            IconButton(
                              iconSize: 36,
                              icon: Icon(Icons.skip_next_rounded,
                                  color: player.hasNext
                                      ? cs.onSurface
                                      : cs.onSurface
                                          .withOpacity(0.3)),
                              onPressed: player.hasNext
                                  ? player.skipNext
                                  : null,
                            ),
                        ],
                      );
                    },
                  ),

                  const Spacer(flex: 3),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _streamCover(StreamTrack st, ColorScheme cs) {
    if (st.thumbnailUrl != null) {
      return CachedNetworkImage(
        imageUrl: st.thumbnailUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _coverFallback(cs),
        errorWidget: (_, __, ___) => _coverFallback(cs),
      );
    }
    return _coverFallback(cs);
  }

  Widget _coverFallback(ColorScheme cs) => Container(
        color: cs.surface,
        child: Icon(Icons.music_note_rounded,
            size: 80, color: cs.onSurface.withOpacity(0.2)),
      );

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}

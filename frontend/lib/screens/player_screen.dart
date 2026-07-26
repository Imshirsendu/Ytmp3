import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

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
          // ── Share button ─────────────────────────────────────────────
          Consumer<PlayerProvider>(
            builder: (ctx, player, _) {
              final now = player.current;
              if (now == null) return const SizedBox.shrink();
              final url = now.isStream
                  ? now.stream!.youtubeUrl
                  : null; // local tracks don't have a URL to share
              if (url == null) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share',
                onPressed: () => Share.share(
                  '🎵 ${now.title} — ${now.artist}\n$url',
                  subject: now.title,
                ),
              );
            },
          ),
          // ── Equalizer button ─────────────────────────────────────────
          Consumer<PlayerProvider>(
            builder: (ctx, player, _) => IconButton(
              icon: const Icon(Icons.equalizer_rounded),
              tooltip: 'Equalizer',
              onPressed: () => _EqSheet.show(context),
            ),
          ),
          // ── Queue button ─────────────────────────────────────────────
          Consumer<PlayerProvider>(
            builder: (ctx, player, _) =>
                !player.current!.isStream && player.queue.isNotEmpty
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

                  // ── Cover art ────────────────────────────────────────
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

                  // ── Title & artist ───────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(now.title,
                                style: tt.titleMedium?.copyWith(fontSize: 18),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(now.artist,
                                      style: tt.bodyMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (now.isStream) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.secondary.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('STREAM',
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
                      // ── Share for local tracks (share file) ──────────
                      if (!now.isStream)
                        IconButton(
                          icon: Icon(Icons.share_outlined,
                              color: cs.onSurface.withOpacity(0.5), size: 20),
                          tooltip: 'Share',
                          onPressed: () => Share.shareXFiles(
                            [XFile(now.local!.filePath)],
                            subject: now.title,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Seek bar ─────────────────────────────────────────
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
                              overlayShape: SliderComponentShape.noOverlay,
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

                  const SizedBox(height: 16),

                  // ── Shuffle / Loop (local only) ──────────────────────
                  if (!now.isStream)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(Icons.shuffle_rounded,
                              color: player.shuffle
                                  ? cs.primary
                                  : cs.onSurface.withOpacity(0.4)),
                          onPressed: player.toggleShuffle,
                          tooltip: 'Shuffle',
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            player.loopMode == AppLoopMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            color: player.loopMode != AppLoopMode.none
                                ? cs.primary
                                : cs.onSurface.withOpacity(0.4),
                          ),
                          onPressed: player.toggleLoop,
                          tooltip: 'Loop',
                        ),
                      ],
                    ),

                  const SizedBox(height: 8),

                  // ── Main controls ────────────────────────────────────
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

                          GestureDetector(
                            onTap: isLoading ? null : player.togglePlayPause,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.primary.withOpacity(0.4),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
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
                                      size: 36,
                                      color: cs.onPrimary,
                                    ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          if (!now.isStream)
                            IconButton(
                              iconSize: 36,
                              icon: Icon(Icons.skip_next_rounded,
                                  color: player.hasNext
                                      ? cs.onSurface
                                      : cs.onSurface.withOpacity(0.3)),
                              onPressed:
                                  player.hasNext ? player.skipNext : null,
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

// ─────────────────────────────────────────────────────────────────────────────
// Equalizer bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EqSheet extends StatelessWidget {
  const _EqSheet();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PlayerProvider>(),
        child: const _EqSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final tt     = Theme.of(context).textTheme;
    final player = context.watch<PlayerProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text('Equalizer', style: tt.titleMedium),
          const SizedBox(height: 4),
          Text(
            player.eqReady
                ? 'Android hardware EQ active'
                : 'EQ unavailable on this device',
            style: tt.labelSmall,
          ),
          const SizedBox(height: 20),

          // Preset chips
          Row(
            children: EqPreset.values.map((preset) {
              final active = player.eqPreset == preset;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => player.setEqPreset(preset),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: active
                            ? cs.primary
                            : cs.onSurface.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? cs.primary
                              : cs.onSurface.withOpacity(0.12),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(preset.emoji,
                              style: const TextStyle(fontSize: 20)),
                          const SizedBox(height: 6),
                          Text(
                            preset.label,
                            style: tt.labelSmall?.copyWith(
                              color: active
                                  ? cs.onPrimary
                                  : cs.onSurface.withOpacity(0.7),
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          if (!player.eqReady) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: cs.onSurface.withOpacity(0.4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Equalizer requires Android. Preset selection is saved for when it becomes available.',
                      style: tt.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

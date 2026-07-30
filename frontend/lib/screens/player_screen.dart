import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
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
          // ── Equalizer — always visible, has active-state colour ───────
          Consumer<PlayerProvider>(
            builder: (ctx, player, _) => IconButton(
              icon: Icon(
                Icons.equalizer_rounded,
                color: player.eqPreset != EqPreset.flat
                    ? cs.primary
                    : null,
              ),
              tooltip: 'Equalizer',
              onPressed: () => _EqSheet.show(context),
            ),
          ),
          // ── Overflow menu ─────────────────────────────────────────────
          Consumer<PlayerProvider>(
            builder: (ctx, player, _) {
              final now = player.current;
              if (now == null) return const SizedBox.shrink();

              return PopupMenuButton<_PlayerAction>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (action) {
                  switch (action) {
                    case _PlayerAction.addToPlaylist:
                      _AddToPlaylistSheet.show(context, now.stream!);
                    case _PlayerAction.share:
                      Share.share(
                        '🎵 ${now.title} — ${now.artist}\n${now.stream!.youtubeUrl}',
                        subject: now.title,
                      );
                    case _PlayerAction.sleepTimer:
                      _SleepTimerSheet.show(context);
                    case _PlayerAction.queue:
                      QueueScreen.show(context);
                  }
                },
                itemBuilder: (_) => [
                  // Add to playlist — streams only
                  if (now.isStream)
                    const PopupMenuItem(
                      value: _PlayerAction.addToPlaylist,
                      child: ListTile(
                        leading: Icon(Icons.playlist_add_rounded),
                        title: Text('Add to playlist'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  // Share — streams only (local uses file share in body)
                  if (now.isStream)
                    const PopupMenuItem(
                      value: _PlayerAction.share,
                      child: ListTile(
                        leading: Icon(Icons.share_outlined),
                        title: Text('Share'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  // Sleep timer — always
                  PopupMenuItem(
                    value: _PlayerAction.sleepTimer,
                    child: ListTile(
                      leading: Icon(
                        Icons.bedtime_outlined,
                        color: player.sleepTimerActive ? cs.primary : null,
                      ),
                      title: Text(
                        player.sleepTimerActive
                            ? 'Sleep timer (on)'
                            : 'Sleep timer',
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  // Queue — local tracks only
                  if (!now.isStream && player.queue.isNotEmpty)
                    const PopupMenuItem(
                      value: _PlayerAction.queue,
                      child: ListTile(
                        leading: Icon(Icons.queue_music_outlined),
                        title: Text('Queue'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                ],
              );
            },
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
                            _MarqueeText(
                              text: now.title,
                              style: tt.titleMedium?.copyWith(fontSize: 18) ??
                                  const TextStyle(fontSize: 18),
                            ),
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

                  // ── Shuffle / Loop ────────────────────────────────────
                  // Show for local queue always; show for streams when a
                  // playlist context is loaded (so the buttons do something)
                  if (!now.isStream || player.hasStreamPlaylist)
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
                      // Use player.playing (backed by _player.playing) so the
                      // button reflects real state even before the stream emits.
                      final isPlaying = player.playing;
                      final processingState = snap.data?.processingState;
                      // For streams: buffering is normal — only spinner on explicit player.loading.
                      // For local: show spinner during initial load/buffer only.
                      final isStream = player.current!.isStream;
                      final isLoading = player.loading ||
                          (!isStream && processingState == ProcessingState.loading) ||
                          (!isStream &&
                              processingState == ProcessingState.buffering &&
                              !isPlaying);

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Prev — always shown; dimmed when unavailable
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

                          // Next — always shown; dimmed when unavailable
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
// Overflow menu actions
// ─────────────────────────────────────────────────────────────────────────────

enum _PlayerAction { addToPlaylist, share, sleepTimer, queue }

// ─────────────────────────────────────────────────────────────────────────────
// Equalizer bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EqSheet extends StatelessWidget {
  const _EqSheet();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      // isScrollControlled lets the sheet grow to its natural height
      // instead of being capped at ~50% of the screen (which clips the
      // bottom on smaller devices).
      isScrollControlled: true,
      // useSafeArea adds bottom padding automatically so the sheet never
      // disappears behind the navigation bar or home indicator.
      useSafeArea: true,
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
      // Use the safe-area bottom inset (home indicator / nav bar) plus extra
      // breathing room so the chips are never flush against the screen edge.
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, 32 + MediaQuery.of(context).padding.bottom),
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

// ─────────────────────────────────────────────────────────────────────────────
// Sleep Timer bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SleepTimerSheet extends StatelessWidget {
  const _SleepTimerSheet();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PlayerProvider>(),
        child: const _SleepTimerSheet(),
      ),
    );
  }

  static const _presets = [
    (label: '15 min', duration: Duration(minutes: 15)),
    (label: '30 min', duration: Duration(minutes: 30)),
    (label: '45 min', duration: Duration(minutes: 45)),
    (label: '60 min', duration: Duration(minutes: 60)),
  ];

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final tt     = Theme.of(context).textTheme;
    final player = context.watch<PlayerProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
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

          Row(
            children: [
              const Text('🌙', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('Sleep Timer', style: tt.titleMedium),
              const Spacer(),
              if (player.sleepTimerActive && player.sleepRemaining != null)
                _CountdownChip(remaining: player.sleepRemaining!),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            player.sleepTimerActive
                ? 'Playback will pause when the timer ends.'
                : 'Pause playback after a set time.',
            style: tt.labelSmall,
          ),
          const SizedBox(height: 20),

          // Preset grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 3.2,
            children: _presets.map((p) {
              return GestureDetector(
                onTap: () {
                  player.setSleepTimer(p.duration);
                  Navigator.pop(context);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: cs.onSurface.withOpacity(0.12)),
                  ),
                  child: Center(
                    child: Text(p.label,
                        style: tt.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.85))),
                  ),
                ),
              );
            }).toList(),
          ),

          if (player.sleepTimerActive) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  player.cancelSleepTimer();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel Timer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.error,
                  side: BorderSide(color: cs.error.withOpacity(0.5)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add to Playlist bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddToPlaylistSheet extends StatelessWidget {
  final StreamTrack stream;
  const _AddToPlaylistSheet({required this.stream});

  static void show(BuildContext context, StreamTrack stream) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PlaylistProvider>(),
        child: _AddToPlaylistSheet(stream: stream),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final tt       = Theme.of(context).textTheme;
    final pp       = context.watch<PlaylistProvider>();
    final playlists = pp.playlists;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
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

          Row(
            children: [
              Text('Add to Playlist', style: tt.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _createAndAdd(context, pp),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No playlists yet — tap New to create one',
                    style: tt.bodyMedium),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: playlists.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final pl = playlists[i];
                  final already = pp.isInPlaylist(pl.id, stream.youtubeUrl);
                  return ListTile(
                    leading: Icon(Icons.queue_music_rounded,
                        color: already ? cs.primary : cs.onSurface.withOpacity(0.5)),
                    title: Text(pl.name, style: tt.titleMedium),
                    subtitle: Text('${pl.items.length} items',
                        style: tt.bodyMedium),
                    trailing: already
                        ? Icon(Icons.check_circle_rounded,
                            color: cs.primary, size: 20)
                        : null,
                    onTap: already
                        ? null
                        : () async {
                            await pp.addItem(
                              pl.id,
                              PlaylistItem.stream(
                                url: stream.youtubeUrl,
                                trackTitle: stream.title,
                                trackArtist: stream.artist,
                                thumb: stream.thumbnailUrl,
                              ),
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Added to ${pl.name}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                              );
                            }
                          },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _createAndAdd(
      BuildContext context, PlaylistProvider pp) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('New Playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final pl = await pp.createPlaylist(name);
    await pp.addItem(
      pl.id,
      PlaylistItem.stream(
        url: stream.youtubeUrl,
        trackTitle: stream.title,
        trackArtist: stream.artist,
        thumb: stream.thumbnailUrl,
      ),
    );
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to $name')),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Marquee text — scrolls right-to-left when text overflows.
// Identical logic to MiniPlayer's _MarqueeText; kept private to this file.
// ─────────────────────────────────────────────────────────────────────────────

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scroll;
  late final AnimationController _controller;

  static const double _gap     = 64.0;  // wider gap for the full-screen player
  static const double _pxPerSec = 35.0;
  static const int    _pauseMs  = 1800;

  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _scroll     = ScrollController();
    _controller = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(_MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _controller.stop();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      setState(() => _needsScroll = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent > 0) {
      setState(() => _needsScroll = true);
      _startLoop();
    }
  }

  void _startLoop() async {
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: _pauseMs));
    if (!mounted) return;
    _runScroll();
  }

  void _runScroll() async {
    while (mounted && _needsScroll && _scroll.hasClients) {
      final maxScroll = _scroll.position.maxScrollExtent;
      if (maxScroll <= 0) break;
      final dur = Duration(
          milliseconds: ((maxScroll + _gap) / _pxPerSec * 1000).round());
      await _scroll.animateTo(maxScroll + _gap,
          duration: dur, curve: Curves.linear);
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      _scroll.jumpTo(0);
      await Future.delayed(const Duration(milliseconds: _pauseMs));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return ClipRect(
        child: SizedBox(
          height: (widget.style.fontSize ?? 18) * 1.4,
          child: _needsScroll
              ? ListView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    Text(widget.text, style: widget.style),
                    SizedBox(width: _gap),
                    Text(widget.text, style: widget.style),
                  ],
                )
              : SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Text(widget.text, style: widget.style),
                ),
        ),
      );
    });
  }
}

class _CountdownChip extends StatelessWidget {
  final Duration remaining;
  const _CountdownChip({required this.remaining});

  String get _label {
    final m = remaining.inMinutes.remainder(60);
    return remaining.inHours > 0
        ? '${remaining.inHours}h ${m}m left'
        : '${m}m left';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            ?.copyWith(color: cs.primary),
      ),
    );
  }
}

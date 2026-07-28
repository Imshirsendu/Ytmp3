import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../screens/featured_playlist_screen.dart';
import '../screens/player_screen.dart';
import '../widgets/cover_art.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnim;

  double _dragOffset = 0;
  static const double _height = 64;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _slideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeIn,
    ));
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _dismiss(BuildContext context) async {
    await _slideController.forward();
    if (!mounted) return;
    await context.read<PlayerProvider>().stopAndDismiss();
    if (mounted) {
      _slideController.reset();
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (ctx, player, _) {
        final now = player.current;
        if (now == null) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;

        return GestureDetector(
          onVerticalDragUpdate: (d) {
            final newOffset =
                (_dragOffset + d.delta.dy).clamp(0.0, _height * 1.5);
            setState(() => _dragOffset = newOffset);
          },
          onVerticalDragEnd: (d) {
            final flingDown =
                d.primaryVelocity != null && d.primaryVelocity! > 400;
            final draggedFar = _dragOffset > _height * 0.45;
            if (flingDown || draggedFar) {
              _dismiss(context);
            } else {
              setState(() => _dragOffset = 0);
            }
          },
          onVerticalDragCancel: () => setState(() => _dragOffset = 0),
          onTap: _dragOffset < 4 ? () => PlayerScreen.show(context) : null,
          child: SlideTransition(
            position: _slideAnim,
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: Opacity(
                opacity:
                    (1 - (_dragOffset / (_height * 1.5))).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF16213E),
                    border: Border(
                      top: BorderSide(
                          color: cs.onSurface.withOpacity(0.08), width: 1),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Main controls row (always 64px) ──────────────
                        SizedBox(
                          height: 64,
                          child: Row(
                            children: [
                              const SizedBox(width: 12),

                              // Cover art
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: now.isStream
                                      ? (now.stream!.thumbnailUrl != null
                                          ? CachedNetworkImage(
                                              imageUrl:
                                                  now.stream!.thumbnailUrl!,
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

                              // Title (marquee) + artist
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _MarqueeText(
                                      text: now.title,
                                      style: tt.titleMedium
                                              ?.copyWith(fontSize: 13) ??
                                          const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      now.artist,
                                      style:
                                          tt.bodyMedium?.copyWith(fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),

                              // Sleep timer indicator
                              if (player.sleepTimerActive)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: _SleepIndicator(
                                      remaining: player.sleepRemaining),
                                ),

                              // Play/pause
                              StreamBuilder<PlayerState>(
                                stream: player.playerStateStream,
                                builder: (ctx, snap) {
                                  final isPlaying =
                                      snap.data?.playing ?? false;
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

                              // Next
                              if (player.hasNext)
                                IconButton(
                                  iconSize: 24,
                                  icon: Icon(Icons.skip_next_rounded,
                                      color: cs.onSurface),
                                  onPressed: player.skipNext,
                                ),

                              const SizedBox(width: 4),
                            ],
                          ),
                        ),

                        // ── Playlist chip — own row below controls ────────
                        // Only shown when playing from a featured playlist.
                        // Sits below everything so it never overlaps controls.
                        if (player.sourceFeaturedPlaylist != null)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 12, right: 12, bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _PlaylistChip(
                                label: player.sourceFeaturedPlaylist!.title,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => FeaturedPlaylistScreen(
                                      playlist:
                                          player.sourceFeaturedPlaylist!,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Marquee text — scrolls right-to-left when the text overflows.
// Only animates when the text is wider than the available space.
// Pauses briefly at the start before scrolling, and loops with a gap.
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

  static const double _gap = 48.0;
  static const double _pxPerSec = 40.0;
  static const int _pauseMs = 1800;

  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
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
    final maxScroll = _scroll.position.maxScrollExtent;
    if (maxScroll > 0) {
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
      final scrollDuration = Duration(
        milliseconds: ((maxScroll + _gap) / _pxPerSec * 1000).round(),
      );
      await _scroll.animateTo(
        maxScroll + _gap,
        duration: scrollDuration,
        curve: Curves.linear,
      );
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: SizedBox(
            height: (widget.style.fontSize ?? 13) * 1.5,
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
      },
    );
  }
}

// ── Go to playlist chip ───────────────────────────────────────────────────────

class _PlaylistChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PlaylistChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 110),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.secondary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.secondary.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music_rounded, size: 12, color: cs.secondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.secondary,
                      fontSize: 10,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
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

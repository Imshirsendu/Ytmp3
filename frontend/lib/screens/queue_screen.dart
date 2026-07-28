import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../widgets/cover_art.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const QueueScreen(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
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
        title: Text('QUEUE', style: tt.labelSmall?.copyWith(letterSpacing: 2)),
        centerTitle: true,
      ),
      body: Consumer<PlayerProvider>(
        builder: (ctx, player, _) {
          final queue        = player.queue;
          final currentIndex = player.currentOrderedIndex;

          if (queue.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music_outlined,
                      size: 56, color: cs.onSurface.withOpacity(0.15)),
                  const SizedBox(height: 16),
                  Text('Queue is empty', style: tt.bodyMedium),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 40),
            // Show a subtle drag handle on each tile.
            buildDefaultDragHandles: false,
            onReorder: player.reorderQueue,
            itemCount: queue.length,
            itemBuilder: (ctx, i) {
              final track      = queue[i];
              final isCurrent  = i == currentIndex;
              final isUpcoming = i > currentIndex;

              return _QueueTile(
                key: ValueKey('${track.filePath}_$i'),
                track: track,
                index: i,
                isCurrent: isCurrent,
                isUpcoming: isUpcoming,
                currentIndex: currentIndex,
                cs: cs,
                tt: tt,
                onTap: () => player.playQueueIndex(i),
                onRemove: isUpcoming || i < currentIndex
                    ? () => player.removeFromQueue(i)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _QueueTile extends StatelessWidget {
  final Track track;
  final int index;
  final bool isCurrent;
  final bool isUpcoming;
  final int currentIndex;
  final ColorScheme cs;
  final TextTheme tt;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _QueueTile({
    super.key,
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.isUpcoming,
    required this.currentIndex,
    required this.cs,
    required this.tt,
    required this.onTap,
    required this.onRemove,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: isCurrent
          ? cs.primary.withOpacity(0.08)
          : Colors.transparent,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: isCurrent ? 1.0 : (isUpcoming ? 1.0 : 0.4),
              child: CoverArt(coverArtBytes: track.coverArt, size: 44),
            ),
            // Equalizer / playing indicator on current track
            if (isCurrent)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.equalizer_rounded,
                    color: cs.primary, size: 20),
              ),
          ],
        ),
        title: Text(
          track.title,
          style: tt.titleMedium?.copyWith(
            color: isCurrent
                ? cs.primary
                : isUpcoming
                    ? cs.onSurface
                    : cs.onSurface.withOpacity(0.4),
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${track.artist} • ${_fmt(track.duration)}',
          style: tt.bodyMedium?.copyWith(
            color: isCurrent
                ? cs.primary.withOpacity(0.7)
                : cs.onSurface.withOpacity(isUpcoming ? 0.5 : 0.3),
            fontSize: 11,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Remove button — not shown for current track
            if (onRemove != null)
              IconButton(
                icon: Icon(Icons.remove_circle_outline_rounded,
                    size: 20, color: cs.onSurface.withOpacity(0.3)),
                onPressed: onRemove,
                tooltip: 'Remove from queue',
              ),
            // Drag handle — only for upcoming tracks (can't reorder past)
            if (isUpcoming)
              ReorderableDragStartListener(
                index: index,
                child: Icon(Icons.drag_handle_rounded,
                    color: cs.onSurface.withOpacity(0.3)),
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

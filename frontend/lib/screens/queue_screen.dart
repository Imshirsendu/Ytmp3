import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../widgets/cover_art.dart';

/// Bottom sheet showing the current playback queue.
/// Call [QueueScreen.show] from anywhere that has a BuildContext.
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QueueScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Consumer<PlayerProvider>(
      builder: (ctx, player, _) {
        final queue   = player.queue;
        final current = player.queueIndex;

        // If streaming or queue is empty, show a simple message
        if (player.current?.isStream == true || queue.isEmpty) {
          return _sheet(
            context,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.queue_music_outlined,
                        size: 48, color: cs.onSurface.withOpacity(0.2)),
                    const SizedBox(height: 12),
                    Text(
                      player.current?.isStream == true
                          ? 'Streaming — no queue'
                          : 'Queue is empty',
                      style: tt.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return _sheet(
          context,
          child: Column(
            children: [
              // Handle + title
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text('Up Next', style: tt.titleMedium),
                    const Spacer(),
                    Text('${queue.length} tracks', style: tt.labelSmall),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Track list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: queue.length,
                  itemBuilder: (ctx, i) {
                    final track   = queue[i];
                    final isCurrent = i == current;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Stack(
                        children: [
                          CoverArt(coverArtBytes: track.coverArt, size: 44),
                          if (isCurrent)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.equalizer_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        track.title,
                        style: tt.titleMedium?.copyWith(
                          fontSize: 13,
                          color: isCurrent ? cs.primary : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.artist,
                        style: tt.bodyMedium?.copyWith(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isCurrent
                          ? Icon(Icons.volume_up_rounded,
                              color: cs.primary, size: 18)
                          : Text(_fmt(track.duration),
                              style: tt.labelSmall),
                      onTap: () {
                        player.playQueueIndex(i);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sheet(BuildContext context, {required Widget child}) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: child,
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../screens/player_screen.dart';
import '../widgets/cover_art.dart';
import '../widgets/mini_player.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;
  final List<Track> allTracks;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.allTracks,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Consumer2<PlaylistProvider, LibraryProvider>(
      builder: (ctx, pp, lib, _) {
        // Build a lookup map: filePath → Track
        final library = {for (final t in lib.tracks) t.filePath: t};
        final tracks = pp.resolveTracks(playlist.id, library);

        return Scaffold(
          backgroundColor: const Color(0xFF0D0D1A),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(playlist.name, style: tt.titleMedium),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(context, pp),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _delete(context, pp),
              ),
            ],
          ),
          body: Column(
            children: [
              // Play all button
              if (tracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final player = context.read<PlayerProvider>();
                        await player.playAll(tracks);
                        if (context.mounted) PlayerScreen.show(context);
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text('Play All (${tracks.length})'),
                    ),
                  ),
                ),

              // Track list (reorderable)
              Expanded(
                child: tracks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.queue_music_outlined,
                                size: 56,
                                color: cs.onSurface.withOpacity(0.15)),
                            const SizedBox(height: 16),
                            Text('No tracks yet', style: tt.bodyMedium),
                            const SizedBox(height: 4),
                            Text(
                                'Go to Library, swipe a track → Add',
                                style: tt.labelSmall),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: tracks.length,
                        onReorder: (oldIdx, newIdx) {
                          if (newIdx > oldIdx) newIdx--;
                          pp.reorderTrack(playlist.id, oldIdx, newIdx);
                        },
                        itemBuilder: (ctx, i) {
                          final track = tracks[i];
                          return ListTile(
                            key: ValueKey(track.filePath),
                            leading: CoverArt(
                                coverArtBytes: track.coverArt, size: 48),
                            title: Text(track.title,
                                style: tt.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${track.artist} • ${_fmt(track.duration)}',
                                style: tt.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      size: 18, color: Colors.red),
                                  onPressed: () => pp.removeTrack(
                                      playlist.id, track.filePath),
                                ),
                                const Icon(Icons.drag_handle_rounded,
                                    size: 18),
                              ],
                            ),
                            onTap: () async {
                              final player = context.read<PlayerProvider>();
                              await player.playAll(tracks, startIndex: i);
                              if (context.mounted) PlayerScreen.show(context);
                            },
                          );
                        },
                      ),
              ),

              const MiniPlayer(),
            ],
          ),
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  Future<void> _rename(BuildContext context, PlaylistProvider pp) async {
    final ctrl = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Rename Playlist'),
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
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await pp.renamePlaylist(playlist.id, name);
    }
  }

  Future<void> _delete(BuildContext context, PlaylistProvider pp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete playlist?'),
        content: Text('Delete "${playlist.name}"? Tracks won\'t be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await pp.deletePlaylist(playlist.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/search_result.dart';
import '../models/track.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/server_provider.dart';
import '../screens/player_screen.dart';
import '../widgets/cover_art.dart';
import '../widgets/mini_player.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Consumer2<PlaylistProvider, LibraryProvider>(
      builder: (ctx, pp, lib, _) {
        final library = {for (final t in lib.tracks) t.filePath: t};
        final items = pp.itemsOf(playlist.id);

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
              // Play all button — plays first local track or streams first item
              if (items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () =>
                          _playItem(context, items.first, library, pp),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text('Play All (${items.length})'),
                    ),
                  ),
                ),

              Expanded(
                child: items.isEmpty
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
                                'Add songs from Search or the player screen',
                                style: tt.labelSmall),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: items.length,
                        onReorder: (oldIdx, newIdx) {
                          if (newIdx > oldIdx) newIdx--;
                          pp.reorderItem(playlist.id, oldIdx, newIdx);
                        },
                        itemBuilder: (ctx, i) {
                          final item = items[i];
                          return _ItemTile(
                            key: ValueKey(item.id),
                            item: item,
                            localTrack: item.isStream
                                ? null
                                : library[item.filePath],
                            onTap: () =>
                                _playItem(context, item, library, pp),
                            onRemove: () =>
                                pp.removeItem(playlist.id, item.id),
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

  /// Plays a single item — streams online items, plays local items from library.
  Future<void> _playItem(
    BuildContext context,
    PlaylistItem item,
    Map<String, Track> library,
    PlaylistProvider pp,
  ) async {
    if (item.isStream) {
      await _streamItem(context, item);
    } else {
      final track = library[item.filePath];
      if (track == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Track not found in library')),
          );
        }
        return;
      }
      // Build local queue from all local items in this playlist
      final allItems = pp.itemsOf(playlist.id);
      final localTracks = allItems
          .where((i) => !i.isStream)
          .map((i) => library[i.filePath])
          .whereType<Track>()
          .toList();
      final startIndex = localTracks.indexOf(track);
      final player = context.read<PlayerProvider>();
      await player.playAll(localTracks,
          startIndex: startIndex < 0 ? 0 : startIndex);
      if (context.mounted) PlayerScreen.show(context);
    }
  }

  /// Resolves a stream item via streamInfoUrl and plays it.
  /// Mirrors the exact same flow as _stream() in search_screen.dart.
  Future<void> _streamItem(BuildContext context, PlaylistItem item) async {
    final server = context.read<ServerProvider>();
    final player = context.read<PlayerProvider>();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Loading stream…'), duration: Duration(seconds: 2)),
    );

    try {
      final res = await Dio().get(
        server.streamInfoUrl(item.youtubeUrl!),
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      final data = res.data as Map<String, dynamic>;
      final st = StreamTrack(
        youtubeUrl:   item.youtubeUrl!,
        streamUrl:    data['stream_url'] as String,
        title:        data['title']      as String? ?? item.title ?? '',
        artist:       data['artist']     as String? ?? item.artist ?? '',
        thumbnailUrl: data['thumbnail']  as String? ?? item.thumbnailUrl,
        duration: Duration(
            seconds: (data['duration'] as num?)?.toInt() ?? 0),
      );
      await player.playStream(st);
      if (context.mounted) PlayerScreen.show(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Stream failed: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
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

// ── Item tile — handles both stream and local items ───────────────────────────

class _ItemTile extends StatelessWidget {
  final PlaylistItem item;
  final Track? localTrack;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ItemTile({
    super.key,
    required this.item,
    required this.localTrack,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final String title;
    final String subtitle;
    final Widget leading;

    if (item.isStream) {
      title    = item.title ?? 'Unknown';
      subtitle = item.artist ?? '';
      leading  = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: item.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: item.thumbnailUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                placeholder: (_, __) => _placeholder(cs),
                errorWidget: (_, __, ___) => _placeholder(cs),
              )
            : _placeholder(cs),
      );
    } else {
      title    = localTrack?.title ?? item.filePath?.split('/').last ?? 'Unknown';
      subtitle = localTrack?.artist ?? '';
      leading  = CoverArt(coverArtBytes: localTrack?.coverArt, size: 48);
    }

    return ListTile(
      key: key,
      leading: leading,
      title: Text(title,
          style: tt.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          if (item.isStream)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.wifi_rounded, size: 11,
                  color: cs.secondary.withOpacity(0.7)),
            ),
          Expanded(
            child: Text(subtitle,
                style: tt.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                size: 18, color: Colors.red),
            onPressed: onRemove,
          ),
          const Icon(Icons.drag_handle_rounded, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _placeholder(ColorScheme cs) => Container(
        width: 48,
        height: 48,
        color: cs.surface,
        child: Icon(Icons.music_note_rounded,
            size: 20, color: cs.onSurface.withOpacity(0.3)),
      );
}

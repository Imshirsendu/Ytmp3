import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/search_result.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/server_provider.dart';
import '../screens/player_screen.dart';

/// Three-dot bottom sheet for a [SearchResult] track inside any playlist screen.
///
/// Shows: Add to Playlist · Add to Queue · Play Next
///
/// Usage:
/// ```dart
/// TrackOptionsSheet.show(context, result);
/// ```
class TrackOptionsSheet extends StatelessWidget {
  final SearchResult result;

  const TrackOptionsSheet({super.key, required this.result});

  static void show(BuildContext context, SearchResult result) {
    final pp = context.read<PlaylistProvider>();
    final player = context.read<PlayerProvider>();
    final server = context.read<ServerProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: pp),
          ChangeNotifierProvider.value(value: player),
          ChangeNotifierProvider.value(value: server),
        ],
        child: TrackOptionsSheet(result: result),
      ),
    );
  }

  String? _thumb() {
    final id = Uri.tryParse(result.url)?.queryParameters['v'];
    if (id != null && id.isNotEmpty) {
      return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
    }
    return result.thumbnail;
  }

  @override
  Widget build(BuildContext context) {
    final tt     = Theme.of(context).textTheme;
    final cs     = Theme.of(context).colorScheme;
    final thumb  = _thumb();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Track info header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: thumb != null
                      ? CachedNetworkImage(
                          imageUrl: thumb,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _thumbPlaceholder(cs),
                        )
                      : _thumbPlaceholder(cs),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.title,
                          style: tt.titleMedium?.copyWith(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(result.uploader,
                          style: tt.bodyMedium?.copyWith(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.6)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          Divider(color: cs.onSurface.withOpacity(0.08)),

          // ── Options ────────────────────────────────────────────────────

          // Add to Playlist
          ListTile(
            leading: Icon(Icons.playlist_add_rounded, color: cs.primary),
            title: Text('Add to Playlist', style: tt.titleMedium),
            onTap: () {
              Navigator.pop(context);
              _showAddToPlaylist(context);
            },
          ),

          // Add to Queue
          ListTile(
            leading: Icon(Icons.queue_music_rounded,
                color: cs.onSurface.withOpacity(0.7)),
            title: Text('Add to Queue', style: tt.titleMedium),
            subtitle: Text('Plays after current queue ends',
                style: tt.bodySmall
                    ?.copyWith(color: cs.onSurface.withOpacity(0.45))),
            onTap: () async {
              Navigator.pop(context);
              await _addToQueue(context, playNext: false);
            },
          ),

          // Play Next
          ListTile(
            leading: Icon(Icons.skip_next_rounded,
                color: cs.onSurface.withOpacity(0.7)),
            title: Text('Play Next', style: tt.titleMedium),
            subtitle: Text('Plays immediately after current track',
                style: tt.bodySmall
                    ?.copyWith(color: cs.onSurface.withOpacity(0.45))),
            onTap: () async {
              Navigator.pop(context);
              await _addToQueue(context, playNext: true);
            },
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Resolves the stream URL then adds the track to queue or play-next slot.
  Future<void> _addToQueue(BuildContext context,
      {required bool playNext}) async {
    final server = context.read<ServerProvider>();
    final player = context.read<PlayerProvider>();

    // Show a brief snackbar while we resolve the stream URL
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          playNext ? 'Resolving stream for Play Next…' : 'Adding to queue…',
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final res = await Dio().get(
        server.streamInfoUrl(result.url),
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      final raw  = res.data;
      final data = (raw is Map<String, dynamic>)
          ? raw
          : jsonDecode(raw as String) as Map<String, dynamic>;
      final st = StreamTrack(
        youtubeUrl:   result.url,
        streamUrl:    data['stream_url'] as String,
        title:        data['title']      as String? ?? result.title,
        artist:       data['artist']     as String? ?? result.uploader,
        thumbnailUrl: data['thumbnail']  as String?,
        duration: Duration(
            seconds: (data['duration'] as num?)?.toInt() ?? 0),
      );

      if (playNext) {
        player.playNextStream(st);
      } else {
        player.addToQueueStream(st);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              playNext
                  ? '"${result.title}" will play next'
                  : '"${result.title}" added to queue',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showAddToPlaylist(BuildContext context) {
    final pp   = context.read<PlaylistProvider>();
    final thumb = _thumb();
    final item = PlaylistItem.stream(
      url:         result.url,
      trackTitle:  result.title,
      trackArtist: result.uploader,
      thumb:       thumb,
    );
    _AddToPlaylistSheet.show(context, pp, item);
  }

  Widget _thumbPlaceholder(ColorScheme cs) => Container(
        width: 52,
        height: 52,
        color: cs.surface,
        child: Icon(Icons.music_note_rounded,
            size: 22, color: cs.onSurface.withOpacity(0.3)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Add-to-playlist sheet (self-contained so this widget has no external deps)
// ─────────────────────────────────────────────────────────────────────────────

class _AddToPlaylistSheet extends StatelessWidget {
  final PlaylistProvider pp;
  final PlaylistItem     item;

  const _AddToPlaylistSheet({required this.pp, required this.item});

  static void show(
      BuildContext context, PlaylistProvider pp, PlaylistItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider.value(
        value: pp,
        child: _AddToPlaylistSheet(pp: pp, item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final tt     = Theme.of(context).textTheme;
    final livepp = context.watch<PlaylistProvider>();
    final lists  = livepp.playlists;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                onPressed: () => _createAndAdd(context, livepp),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (lists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No playlists yet — tap New to create one',
                    style: tt.bodyMedium),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: lists.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final pl      = lists[i];
                  final already = livepp.isInPlaylist(pl.id, item.id);
                  return ListTile(
                    leading: Icon(Icons.queue_music_rounded,
                        color: already
                            ? cs.primary
                            : cs.onSurface.withOpacity(0.5)),
                    title:    Text(pl.name, style: tt.titleMedium),
                    subtitle: Text('${pl.items.length} items',
                        style: tt.bodyMedium),
                    trailing: already
                        ? Icon(Icons.check_circle_rounded,
                            color: cs.primary, size: 20)
                        : null,
                    onTap: already
                        ? null
                        : () async {
                            await livepp.addItem(pl.id, item);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Added to ${pl.name}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
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
      BuildContext context, PlaylistProvider livepp) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('New Playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'Playlist name'),
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
    final pl = await livepp.createPlaylist(name);
    await livepp.addItem(pl.id, item);
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to $name')),
      );
    }
  }
}

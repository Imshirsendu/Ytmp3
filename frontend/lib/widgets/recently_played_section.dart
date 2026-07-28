import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/recently_played_provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/server_provider.dart';
import '../models/search_result.dart';
import '../screens/player_screen.dart';

/// Drop this widget anywhere — it shows up to 10 recently played
/// tracks/streams in a horizontal scrolling row.
class RecentlyPlayedSection extends StatelessWidget {
  const RecentlyPlayedSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RecentlyPlayedProvider>(
      builder: (ctx, rp, _) {
        final entries = rp.entries;
        if (entries.isEmpty) return const SizedBox.shrink();

        final tt = Theme.of(context).textTheme;
        final cs = Theme.of(context).colorScheme;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Text('Recently Played', style: tt.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => rp.clear(),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4)),
                    child: Text('Clear',
                        style: TextStyle(
                            color: cs.onSurface.withOpacity(0.4),
                            fontSize: 11)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) => _RecentCard(entry: entries[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecentCard extends StatelessWidget {
  final RecentEntry entry;
  const _RecentCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _play(context),
      child: Stack(
        children: [
          Container(
            width: 130,
            decoration: BoxDecoration(
              color: const Color(0xFF16213E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  child: _thumb(cs),
                ),
                // Title + artist
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
                  child: Text(
                    entry.title,
                    style: tt.labelMedium?.copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 1, 8, 0),
                  child: Text(
                    entry.artist,
                    style: tt.labelSmall?.copyWith(
                        fontSize: 10,
                        color: cs.onSurface.withOpacity(0.5)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // ── Dismiss button ───────────────────────────────────────────
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () =>
                  context.read<RecentlyPlayedProvider>().removeEntry(entry.id),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(ColorScheme cs) {
    const h = 62.0;
    if (entry.thumbnailUrl != null) {
      return CachedNetworkImage(
        imageUrl: entry.thumbnailUrl!,
        width: 130,
        height: h,
        fit: BoxFit.cover,
        placeholder: (_, __) => _placeholder(cs, h),
        errorWidget: (_, __, ___) => _placeholder(cs, h),
      );
    }
    return _placeholder(cs, h);
  }

  Widget _placeholder(ColorScheme cs, double h) => Container(
        width: 130,
        height: h,
        color: cs.surface,
        child: Icon(Icons.music_note_rounded,
            size: 24, color: cs.onSurface.withOpacity(0.2)),
      );

  Future<void> _play(BuildContext context) async {
    final player = context.read<PlayerProvider>();

    if (entry.isStream) {
      // ── Re-stream using the stored YouTube URL ──────────────────────
      // Mirrors the exact same flow as _stream() in search_screen.dart.
      final server = context.read<ServerProvider>();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Loading stream…'),
            duration: Duration(seconds: 2)),
      );

      try {
        final res = await Dio().get(
          server.streamInfoUrl(entry.id), // entry.id == youtubeUrl for streams
          options: Options(receiveTimeout: const Duration(seconds: 25)),
        );
        final data = res.data as Map<String, dynamic>;
        final st = StreamTrack(
          youtubeUrl:   entry.id,
          streamUrl:    data['stream_url'] as String,
          title:        data['title']      as String? ?? entry.title,
          artist:       data['artist']     as String? ?? entry.artist,
          thumbnailUrl: data['thumbnail']  as String? ?? entry.thumbnailUrl,
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
      return;
    }

    // ── Local track — look it up from the library and play it ─────────
    final lib = context.read<LibraryProvider>();
    final track = lib.trackMap[entry.id];
    if (track == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Track not found in library')),
      );
      return;
    }
    await player.playAll([track], startIndex: 0);
    if (context.mounted) PlayerScreen.show(context);
  }
}

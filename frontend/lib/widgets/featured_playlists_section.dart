import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/featured_playlist.dart';
import '../providers/server_provider.dart';
import '../screens/featured_playlist_screen.dart';

class FeaturedPlaylistsSection extends StatelessWidget {
  const FeaturedPlaylistsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text('Featured Playlists', style: tt.titleMedium),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: kFeaturedPlaylists.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) =>
              _PlaylistCard(playlist: kFeaturedPlaylists[i]),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Playlist card (vertical, full width) ─────────────────────────────────────

class _PlaylistCard extends StatefulWidget {
  final FeaturedPlaylist playlist;
  const _PlaylistCard({required this.playlist});

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  List<String> _thumbnails = [];
  bool _fetched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_fetched) {
      _fetched = true;
      _fetchThumbnails();
    }
  }

  Future<void> _fetchThumbnails() async {
    final server = context.read<ServerProvider>();
    if (!server.isOnline) return;
    try {
      final res = await Dio().get(
        '${server.serverUrl}/search',
        queryParameters: {'q': widget.playlist.searchQuery, 'limit': 4},
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      final results = (res.data['results'] as List? ?? []);
      final thumbs = results
          .map((e) => e['thumbnail'] as String?)
          .whereType<String>()
          .take(4)
          .toList();
      if (mounted) setState(() => _thumbnails = thumbs);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pl = widget.playlist;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FeaturedPlaylistScreen(playlist: pl),
        ),
      ),
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: pl.gradient.first.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Thumbnail collage ──────────────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14)),
              child: SizedBox(
                width: 88,
                height: 88,
                child: _thumbnails.length >= 4
                    ? _CollageGrid(thumbnails: _thumbnails)
                    : _thumbnails.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: _thumbnails.first,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                _gradientFallback(pl),
                            errorWidget: (_, __, ___) =>
                                _gradientFallback(pl),
                          )
                        : _gradientFallback(pl),
              ),
            ),

            // ── Info ───────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text(pl.emoji,
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            pl.title,
                            style: tt.titleMedium?.copyWith(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pl.subtitle,
                      style: tt.bodyMedium?.copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

            // ── Arrow ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: pl.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientFallback(FeaturedPlaylist pl) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: pl.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(pl.emoji,
              style: const TextStyle(fontSize: 32)),
        ),
      );
}

// ── 2x2 collage grid ─────────────────────────────────────────────────────────

class _CollageGrid extends StatelessWidget {
  final List<String> thumbnails;
  const _CollageGrid({required this.thumbnails});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 1,
      crossAxisSpacing: 1,
      children: thumbnails.take(4).map((url) {
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: const Color(0xFF1A1A2E)),
          errorWidget: (_, __, ___) =>
              Container(color: const Color(0xFF1A1A2E)),
        );
      }).toList(),
    );
  }
}

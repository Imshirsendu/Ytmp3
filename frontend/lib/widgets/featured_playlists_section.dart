import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/featured_playlist.dart';
import '../providers/server_provider.dart';
import '../screens/featured_playlist_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Root section widget — composes Trending, Artist Radio, Moods, Featured
// ─────────────────────────────────────────────────────────────────────────────

class FeaturedPlaylistsSection extends StatelessWidget {
  const FeaturedPlaylistsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TrendingSection(),
        _ArtistRadioSection(),
        _MoodSection(),
        _FeaturedSection(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trending Now — daily-refreshed single card
// ─────────────────────────────────────────────────────────────────────────────

class _TrendingSection extends StatefulWidget {
  const _TrendingSection();

  @override
  State<_TrendingSection> createState() => _TrendingSectionState();
}

class _TrendingSectionState extends State<_TrendingSection> {
  static const _cacheKey     = 'trending_thumbs_v2';
  static const _cacheTimeKey = 'trending_thumbs_time_v2';

  List<String> _thumbnails = [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _loadThumbnails();
    }
  }

  Future<void> _loadThumbnails() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetch = prefs.getInt(_cacheTimeKey) ?? 0;
    final now       = DateTime.now().millisecondsSinceEpoch;
    final stale     = (now - lastFetch) > const Duration(hours: 24).inMilliseconds;

    if (!stale) {
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        final list = (jsonDecode(cached) as List).cast<String>();
        if (mounted) setState(() => _thumbnails = list);
        return;
      }
    }

    // Fetch fresh thumbnails from first two queries in parallel
    final server = context.read<ServerProvider>();
    if (!server.isOnline) return;

    try {
      final queries = kTrendingPlaylist.searchQueries.take(2).toList();
      final futures = queries.map((q) async {
        try {
          final res = await Dio().get(
            '${server.serverUrl}/search',
            queryParameters: {'q': q, 'limit': 2},
            options: Options(receiveTimeout: const Duration(seconds: 15)),
          );
          return (res.data['results'] as List? ?? [])
              .map((e) {
                final url = e['url'] as String? ?? '';
                final id  = Uri.tryParse(url)?.queryParameters['v'];
                if (id != null && id.isNotEmpty) {
                  return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
                }
                return e['thumbnail'] as String?;
              })
              .whereType<String>()
              .toList();
        } catch (_) {
          return <String>[];
        }
      });

      final results = await Future.wait(futures);
      final thumbs = results.expand((x) => x).take(4).toList();

      await prefs.setString(_cacheKey, jsonEncode(thumbs));
      await prefs.setInt(_cacheTimeKey, now);

      if (mounted) setState(() => _thumbnails = thumbs);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pl = kTrendingPlaylist;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Text('🔥  Trending Now', style: tt.titleMedium),
              const Spacer(),
              Text('Daily refresh',
                  style: tt.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.4))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _PlaylistCard(playlist: pl, prefetchedThumbs: _thumbnails),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Artist Radio — text input → FeaturedPlaylistScreen
// ─────────────────────────────────────────────────────────────────────────────

class _ArtistRadioSection extends StatefulWidget {
  const _ArtistRadioSection();

  @override
  State<_ArtistRadioSection> createState() => _ArtistRadioSectionState();
}

class _ArtistRadioSectionState extends State<_ArtistRadioSection> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _launch(String artist) {
    final name = artist.trim();
    if (name.isEmpty) return;
    FocusScope.of(context).unfocus();
    _ctrl.clear();

    // Artist Radio generates 5 targeted queries for variety
    final playlist = FeaturedPlaylist(
      id:          'artist_radio_${name.toLowerCase().replaceAll(' ', '_')}',
      title:       '$name Radio',
      subtitle:    'Best of $name',
      searchQueries: [
        '$name best songs official audio',
        '$name hits official video',
        '$name popular songs official',
        '$name top tracks official audio',
        '$name latest songs official',
      ],
      gradient:    const [Color(0xFF6C63FF), Color(0xFF3B82F6)],
      icon:        Icons.radio_rounded,
      emoji:       '📻',
      limitPerQuery: 8,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeaturedPlaylistScreen(playlist: playlist),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Text('📻  Artist Radio', style: tt.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.search,
            onSubmitted: _launch,
            decoration: InputDecoration(
              hintText: 'Enter an artist name…',
              prefixIcon: const Icon(Icons.person_search_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(Icons.arrow_forward_rounded,
                    color: cs.primary, size: 20),
                onPressed: () => _launch(_ctrl.text),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mood playlists — 2-column grid
// ─────────────────────────────────────────────────────────────────────────────

class _MoodSection extends StatelessWidget {
  const _MoodSection();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text('🎭  Moods', style: tt.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: kMoodPlaylists
                .map((pl) => _MoodChip(playlist: pl))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _MoodChip extends StatelessWidget {
  final FeaturedPlaylist playlist;
  const _MoodChip({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pl = playlist;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FeaturedPlaylistScreen(playlist: pl),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: pl.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Text(pl.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(pl.title,
                      style: tt.titleMedium?.copyWith(
                          color: Colors.white, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(pl.subtitle,
                      style: tt.labelSmall
                          ?.copyWith(color: Colors.white70, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Featured playlists — vertical list
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturedSection extends StatelessWidget {
  const _FeaturedSection();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared playlist card (Trending + Featured)
// Card thumbnail uses only the FIRST query — fast, one request per card.
// The full multi-query fetch only happens when the user opens the playlist.
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistCard extends StatefulWidget {
  final FeaturedPlaylist playlist;
  final List<String> prefetchedThumbs;

  const _PlaylistCard({
    required this.playlist,
    this.prefetchedThumbs = const [],
  });

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  List<String> _thumbnails = [];
  bool _fetched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.prefetchedThumbs.isNotEmpty) {
      _thumbnails = widget.prefetchedThumbs;
      _fetched = true;
      return;
    }
    if (!_fetched) {
      _fetched = true;
      _fetchThumbnails();
    }
  }

  @override
  void didUpdateWidget(_PlaylistCard old) {
    super.didUpdateWidget(old);
    if (widget.prefetchedThumbs.isNotEmpty &&
        widget.prefetchedThumbs != _thumbnails) {
      setState(() => _thumbnails = widget.prefetchedThumbs);
    }
  }

  /// For the card preview we only fire the FIRST query (fast).
  /// We ask for 4 results so we can fill the 2×2 collage grid.
  Future<void> _fetchThumbnails() async {
    final server = context.read<ServerProvider>();
    if (!server.isOnline) return;
    try {
      final res = await Dio().get(
        '${server.serverUrl}/search',
        queryParameters: {
          'q':     widget.playlist.searchQueries.first,
          'limit': 4,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        ),
      );
      final thumbs = (res.data['results'] as List? ?? [])
          .map((e) {
            final url = e['url'] as String? ?? '';
            final id  = Uri.tryParse(url)?.queryParameters['v'];
            if (id != null && id.isNotEmpty) {
              return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
            }
            return e['thumbnail'] as String?;
          })
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
            // Thumbnail collage
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(14)),
              child: SizedBox(
                width: 88,
                height: 88,
                child: _thumbnails.length >= 4
                    ? _CollageGrid(thumbnails: _thumbnails)
                    : _thumbnails.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: _thumbnails.first,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _gradientFallback(pl),
                            errorWidget: (_, __, ___) => _gradientFallback(pl),
                          )
                        : _gradientFallback(pl),
              ),
            ),

            // Info
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

            // Play button
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
          child: Text(pl.emoji, style: const TextStyle(fontSize: 32)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// 2×2 collage grid
// ─────────────────────────────────────────────────────────────────────────────

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
          placeholder: (_, __) =>
              Container(color: const Color(0xFF1A1A2E)),
          errorWidget: (_, __, ___) =>
              Container(color: const Color(0xFF1A1A2E)),
        );
      }).toList(),
    );
  }
}

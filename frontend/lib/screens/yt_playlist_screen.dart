import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/featured_playlist.dart';
import '../models/search_result.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/server_provider.dart';
import '../screens/player_screen.dart';
import '../widgets/featured_playlists_section.dart'; // for kFeaturedPlaylists
import '../widgets/mini_player.dart';
import '../widgets/track_options_sheet.dart';

/// A YouTube playlist discovered via search.
class YtPlaylistResult {
  final String id;           // YouTube playlist ID (PLxxxxx)
  final String title;
  final String channelName;
  final String? thumbnailUrl;
  final int? videoCount;

  const YtPlaylistResult({
    required this.id,
    required this.title,
    required this.channelName,
    this.thumbnailUrl,
    this.videoCount,
  });

  factory YtPlaylistResult.fromJson(Map<String, dynamic> j) {
    return YtPlaylistResult(
      id:           j['id']           as String? ?? '',
      title:        j['title']        as String? ?? 'Untitled Playlist',
      channelName:  j['uploader']     as String? ??
                    j['channel']      as String? ?? '',
      thumbnailUrl: j['thumbnail']    as String?,
      videoCount:   (j['video_count'] as num?)?.toInt() ??
                    (j['videoCount']  as num?)?.toInt(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class YtPlaylistScreen extends StatefulWidget {
  final YtPlaylistResult playlist;

  const YtPlaylistScreen({super.key, required this.playlist});

  static void show(BuildContext context, YtPlaylistResult playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => YtPlaylistScreen(playlist: playlist),
      ),
    );
  }

  @override
  State<YtPlaylistScreen> createState() => _YtPlaylistScreenState();
}

class _YtPlaylistScreenState extends State<YtPlaylistScreen> {
  final _dio = Dio();

  List<SearchResult> _tracks   = [];
  bool   _loading              = true;
  String? _error;

  final _streaming  = <String>{};
  final _downloaded = <String>{};

  // Whether this playlist has been pinned to the home featured section
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    _fetchTracks();
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> _fetchTracks() async {
    setState(() { _loading = true; _error = null; });

    final server = context.read<ServerProvider>();
    if (!server.isOnline) {
      setState(() { _loading = false; _error = 'Server is offline'; });
      return;
    }

    try {
      // Try playlist endpoint first; fall back to search with playlist id
      final res = await _dio.get(
        '${server.serverUrl}/playlist',
        queryParameters: {'id': widget.playlist.id, 'limit': 50},
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );

      final rawList = res.data['results'] as List? ??
                      res.data['entries']  as List? ??
                      res.data['tracks']   as List? ?? [];

      final seen   = <String>{};
      final merged = <SearchResult>[];

      for (final e in rawList) {
        final track = SearchResult.fromJson(e as Map<String, dynamic>);
        if (seen.contains(track.id)) continue;
        seen.add(track.id);
        merged.add(track);
      }

      setState(() { _tracks = merged; _loading = false; });
    } on DioException catch (e) {
      // If /playlist doesn't exist on this server, fall back to search
      if (e.response?.statusCode == 404 ||
          e.type == DioExceptionType.connectionError) {
        await _fetchViaSearch();
      } else {
        setState(() { _loading = false; _error = e.message ?? e.toString(); });
      }
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  /// Fallback: search using playlist title, grab top 30 results
  Future<void> _fetchViaSearch() async {
    final server = context.read<ServerProvider>();
    try {
      final res = await _dio.get(
        '${server.serverUrl}/search',
        queryParameters: {
          'q':     widget.playlist.title,
          'limit': 30,
        },
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      final rawList = res.data['results'] as List? ?? [];
      final merged  = rawList
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() { _tracks = merged; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Stream ─────────────────────────────────────────────────────────────────

  Future<void> _streamTrack(SearchResult result,
      {bool andOpenPlayer = true}) async {
    final server = context.read<ServerProvider>();
    final player = context.read<PlayerProvider>();

    setState(() => _streaming.add(result.id));
    try {
      final res = await _dio.get(
        server.streamInfoUrl(result.url),
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      final data = res.data as Map<String, dynamic>;
      final st = StreamTrack(
        youtubeUrl:   result.url,
        streamUrl:    data['stream_url'] as String,
        title:        data['title']      as String? ?? result.title,
        artist:       data['artist']     as String? ?? result.uploader,
        thumbnailUrl: data['thumbnail']  as String?,
        duration: Duration(
            seconds: (data['duration'] as num?)?.toInt() ?? 0),
      );
      // Pass full playlist context so prev/next works in player
      final index = _tracks.indexOf(result);
      await player.playStreamFromPlaylist(
        st,
        playlist:  _tracks,
        index:     index < 0 ? 0 : index,
        serverUrl: server.serverUrl,
      );
      if (andOpenPlayer && context.mounted) PlayerScreen.show(context);
    } catch (e) {
      if (context.mounted) {
        String msg = 'Stream failed';
        if (e is DioException) {
          final detail = e.response?.data?['detail'];
          msg = detail != null
              ? 'Stream failed: $detail'
              : 'Stream failed: ${e.message}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _streaming.remove(result.id));
    }
  }

  // ── Download ───────────────────────────────────────────────────────────────

  void _downloadTrack(SearchResult result) {
    final server = context.read<ServerProvider>();
    context.read<DownloadProvider>().enqueue(
          result.url,
          server.downloadUrl(result.url),
          title: result.title,
        );
    setState(() => _downloaded.add(result.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading: ${result.title}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _downloadAll() {
    if (_tracks.isEmpty) return;
    int enqueued = 0;
    for (final t in _tracks) {
      if (_downloaded.contains(t.id)) continue;
      _downloadTrack(t);
      enqueued++;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enqueued == 0 ? 'All tracks already downloaded' : 'Downloading $enqueued tracks…',
        ),
      ),
    );
  }

  // ── Play All ───────────────────────────────────────────────────────────────

  Future<void> _playAll({bool shuffled = false}) async {
    if (_tracks.isEmpty) return;
    final list =
        shuffled ? (List<SearchResult>.from(_tracks)..shuffle()) : _tracks;
    await _streamTrack(list.first);
  }

  // ── Pin to Home ────────────────────────────────────────────────────────────

  void _pinToHome() {
    final pl = widget.playlist;
    // Build a FeaturedPlaylist using the playlist title as the single search query
    // with a generous limit so it loads many songs.
    final featured = FeaturedPlaylist(
      id:            'yt_${pl.id}',
      title:         pl.title,
      subtitle:      pl.channelName,
      emoji:         '🎵',
      icon:          Icons.queue_music_rounded,
      gradient:      const [Color(0xFF6C63FF), Color(0xFF3A3080)],
      searchQueries: [pl.title],
      limitPerQuery: 30,
    );
    // kFeaturedPlaylists is a runtime-mutable list — we append to it.
    kFeaturedPlaylists.add(featured);
    setState(() => _pinned = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${pl.title}" added to home screen')),
    );
  }

  // ── Thumbnails for header collage ──────────────────────────────────────────

  String? _ytThumb(String url) {
    final id = Uri.tryParse(url)?.queryParameters['v'];
    if (id == null || id.isEmpty) return null;
    return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  }

  List<String> get _headerThumbnails => _tracks
      .take(4)
      .map((t) => _ytThumb(t.url) ?? t.thumbnail)
      .whereType<String>()
      .toList();

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pl = widget.playlist;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Column(
        children: [
          // Header
          _YtPlaylistHeader(
            playlist:    pl,
            trackCount:  _tracks.length,
            thumbnails:  _headerThumbnails,
            pinned:      _pinned,
            onPin:       _pinToHome,
          ),

          // Action row
          if (!_loading && _error == null && _tracks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _playAll,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play All'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _playAll(shuffled: true),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.primary,
                        side: BorderSide(color: cs.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _downloadAll,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.secondary,
                      side: BorderSide(color: cs.secondary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                    child: const Icon(Icons.download_rounded, size: 20),
                  ),
                ],
              ),
            ),

          // Track list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _fetchTracks)
                    : _tracks.isEmpty
                        ? Center(
                            child: Text('No tracks found',
                                style: tt.bodyMedium))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 100),
                            itemCount: _tracks.length,
                            itemBuilder: (ctx, i) {
                              final t = _tracks[i];
                              return _TrackTile(
                                index:        i + 1,
                                result:       t,
                                isStreaming:  _streaming.contains(t.id),
                                isDownloaded: _downloaded.contains(t.id),
                                onStream:     () => _streamTrack(t),
                                onDownload:   () => _downloadTrack(t),
                                onOptions:    () => TrackOptionsSheet.show(ctx, t),
                              );
                            },
                          ),
          ),

          const MiniPlayer(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _YtPlaylistHeader extends StatelessWidget {
  final YtPlaylistResult playlist;
  final int              trackCount;
  final List<String>     thumbnails;
  final bool             pinned;
  final VoidCallback     onPin;

  const _YtPlaylistHeader({
    required this.playlist,
    required this.trackCount,
    required this.thumbnails,
    required this.pinned,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pl = playlist;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3A1C71), Color(0xFF6C4FBF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top row: back + pin button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  // Pin to home button
                  Tooltip(
                    message: pinned
                        ? 'Added to home'
                        : 'Add to home screen',
                    child: IconButton(
                      icon: Icon(
                        pinned
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_add_outlined,
                        color: pinned ? Colors.amber : Colors.white,
                      ),
                      onPressed: pinned ? null : onPin,
                    ),
                  ),
                ],
              ),
            ),

            // Collage + info
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Row(
                children: [
                  // Thumbnail / collage
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: thumbnails.length >= 4
                          ? _CollageGrid(thumbnails: thumbnails)
                          : thumbnails.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: thumbnails.first,
                                  fit: BoxFit.cover,
                                )
                              : pl.thumbnailUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: pl.thumbnailUrl!,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          _fallbackBox(),
                                    )
                                  : _fallbackBox(),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Title / channel / count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pl.title,
                            style: tt.headlineMedium?.copyWith(
                                color: Colors.white, fontSize: 20),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(pl.channelName,
                            style: tt.bodyMedium
                                ?.copyWith(color: Colors.white70),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (pl.videoCount != null)
                              _Chip('${pl.videoCount} videos'),
                            if (trackCount > 0) ...[
                              if (pl.videoCount != null)
                                const SizedBox(width: 6),
                              _Chip('$trackCount loaded'),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackBox() => Container(
        color: const Color(0xFF3A1C71),
        child: const Center(
          child: Icon(Icons.queue_music_rounded,
              size: 36, color: Colors.white54),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Colors.white)),
    );
  }
}

class _CollageGrid extends StatelessWidget {
  final List<String> thumbnails;
  const _CollageGrid({required this.thumbnails});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 1.5,
      crossAxisSpacing: 1.5,
      children: thumbnails.take(4).map((url) {
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) =>
              Container(color: Colors.white.withOpacity(0.1)),
          errorWidget: (_, __, ___) =>
              Container(color: Colors.white.withOpacity(0.1)),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Track tile
// ─────────────────────────────────────────────────────────────────────────────

class _TrackTile extends StatelessWidget {
  final int          index;
  final SearchResult result;
  final bool         isStreaming;
  final bool         isDownloaded;
  final VoidCallback onStream;
  final VoidCallback onDownload;
  final VoidCallback onOptions;

  const _TrackTile({
    required this.index,
    required this.result,
    required this.isStreaming,
    required this.isDownloaded,
    required this.onStream,
    required this.onDownload,
    required this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            child: Text('$index',
                style: tt.labelSmall
                    ?.copyWith(color: cs.onSurface.withOpacity(0.4)),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Builder(builder: (ctx) {
              final id = Uri.tryParse(result.url)?.queryParameters['v'];
              final thumb = (id != null && id.isNotEmpty)
                  ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg'
                  : result.thumbnail;
              return thumb != null
                  ? CachedNetworkImage(
                      imageUrl: thumb,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(cs),
                      errorWidget: (_, __, ___) => _placeholder(cs),
                    )
                  : _placeholder(cs);
            }),
          ),
        ],
      ),
      title: Text(result.title,
          style: tt.titleMedium?.copyWith(fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${result.uploader}'
        '${result.durationLabel.isNotEmpty ? ' • ${result.durationLabel}' : ''}',
        style: tt.bodyMedium?.copyWith(fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isStreaming
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: Icon(Icons.play_circle_outline_rounded,
                      color: cs.secondary, size: 26),
                  tooltip: 'Stream',
                  onPressed: onStream,
                ),
          isDownloaded
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.check_circle,
                      color: Colors.green, size: 22),
                )
              : IconButton(
                  icon: Icon(Icons.download_outlined,
                      color: cs.primary, size: 22),
                  tooltip: 'Download',
                  onPressed: onDownload,
                ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded,
                color: cs.onSurface.withOpacity(0.5), size: 20),
            tooltip: 'More options',
            onPressed: onOptions,
          ),
        ],
      ),
      onTap: onStream,
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

// ─────────────────────────────────────────────────────────────────────────────
// Error view
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String       error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 48, color: cs.error.withOpacity(0.6)),
            const SizedBox(height: 12),
            Text(error,
                style: tt.bodyMedium?.copyWith(color: cs.error),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

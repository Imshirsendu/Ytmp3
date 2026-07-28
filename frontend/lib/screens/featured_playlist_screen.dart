import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/featured_playlist.dart';
import '../models/search_result.dart';
import '../models/track.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/server_provider.dart';
import '../screens/player_screen.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_options_sheet.dart';

class FeaturedPlaylistScreen extends StatefulWidget {
  final FeaturedPlaylist playlist;

  const FeaturedPlaylistScreen({super.key, required this.playlist});

  @override
  State<FeaturedPlaylistScreen> createState() => _FeaturedPlaylistScreenState();
}

class _FeaturedPlaylistScreenState extends State<FeaturedPlaylistScreen> {
  final _dio = Dio();
  List<SearchResult> _tracks = [];
  bool _loading = true;
  String? _error;

  final _streaming  = <String>{};
  final _downloaded = <String>{};

  @override
  void initState() {
    super.initState();
    _fetchTracks();
  }

  /// Fires all searchQueries in parallel, merges results, deduplicates by
  /// normalized title so the same song from two queries only appears once.
  Future<void> _fetchTracks() async {
    setState(() { _loading = true; _error = null; });

    final server = context.read<ServerProvider>();
    if (!server.isOnline) {
      setState(() { _loading = false; _error = 'Server is offline'; });
      return;
    }

    try {
      // Fire every query concurrently
      final futures = widget.playlist.searchQueries.map((q) async {
        try {
          final res = await _dio.get(
            '${server.serverUrl}/search',
            queryParameters: {
              'q':     q,
              'limit': widget.playlist.limitPerQuery,
            },
            options: Options(receiveTimeout: const Duration(seconds: 20)),
          );
          return (res.data['results'] as List? ?? [])
              .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {
          // If one query fails, skip it — others still contribute
          return <SearchResult>[];
        }
      });

      final results = await Future.wait(futures);

      // Flatten, filter, deduplicate
      final seen = <String>{};
      final merged = <SearchResult>[];

      for (final batch in results) {
        for (final track in batch) {
          // Skip mashups / jukeboxes (> 20 min)
          if (track.duration != null && track.duration! > 1200) continue;

          // Normalize: lowercase, strip punctuation and common suffixes
          final normalized = _normalize(track.title);
          if (seen.contains(normalized)) continue;

          seen.add(normalized);
          merged.add(track);
        }
      }

      setState(() {
        _tracks  = merged;
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  /// Normalize a title for deduplication:
  /// lower-case → strip parens/brackets content → strip common suffixes
  /// → collapse whitespace.
  String _normalize(String title) {
    return title
        .toLowerCase()
        // Remove content in parens/brackets e.g. "(Official Audio)", "[HD]"
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        // Strip common suffix words
        .replaceAll(
            RegExp(
                r'\b(official|audio|video|full|song|music|hd|4k|lyric|lyrics|ft|feat|remastered)\b'),
            '')
        // Strip non-alphanumeric (except spaces)
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        // Collapse whitespace
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _streamTrack(SearchResult result,
      {bool andOpenPlayer = true}) async {
    final server = context.read<ServerProvider>();
    final player = context.read<PlayerProvider>();

    setState(() => _streaming.add(result.id));
    try {
      final streamUrl = server.streamInfoUrl(result.url);
      debugPrint('▶ STREAM REQUEST: $streamUrl');
      final res = await _dio.get(
        streamUrl,
        options: Options(receiveTimeout: const Duration(seconds: 45)),
      );
      final raw  = res.data;
      final data = (raw is Map<String, dynamic>)
          ? raw
          : jsonDecode(raw as String) as Map<String, dynamic>;
      final st = StreamTrack(
        youtubeUrl:   result.url,
        streamUrl:    data['stream_url'] as String,
        title:        data['title']     as String? ?? result.title,
        artist:       data['artist']    as String? ?? result.uploader,
        thumbnailUrl: data['thumbnail'] as String?,
        duration: Duration(
            seconds: (data['duration'] as num?)?.toInt() ?? 0),
      );
      // Pass full playlist context so prev/next works in player
      final index = _tracks.indexOf(result);
      await player.playStreamFromPlaylist(
        st,
        playlist:         _tracks,
        index:            index < 0 ? 0 : index,
        serverUrl:        server.serverUrl,
        featuredPlaylist: widget.playlist,
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
          debugPrint(
              '▶ STREAM ERROR: ${e.response?.statusCode} — ${e.response?.data}');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _streaming.remove(result.id));
    }
  }

  Future<void> _playAll({bool shuffled = false}) async {
    if (_tracks.isEmpty) return;
    final results =
        shuffled ? (List<SearchResult>.from(_tracks)..shuffle()) : _tracks;
    await _streamTrack(results.first);
  }

  void _downloadAll() {
    if (_tracks.isEmpty) return;
    final dl = context.read<DownloadProvider>();
    final activeOrDoneTitles = dl.jobs
        .where((j) => j.status == DownloadStatus.downloading ||
                      j.status == DownloadStatus.done)
        .map((j) => j.title)
        .toSet();

    int enqueued = 0;
    for (final result in _tracks) {
      if (activeOrDoneTitles.contains(result.title)) continue;
      _downloadTrack(result);
      enqueued++;
    }
    if (enqueued == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All tracks already downloaded')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading $enqueued tracks…')),
      );
    }
  }

  void _downloadTrack(SearchResult result) {
    final server = context.read<ServerProvider>();
    context.read<DownloadProvider>().enqueue(
          result.url,
          server.downloadUrl(result.url),
          title: result.title,
        );
  }

  /// Extracts video ID from a YouTube watch URL and returns hqdefault.jpg.
  String? _ytThumb(String url) {
    final id = Uri.tryParse(url)?.queryParameters['v'];
    if (id == null || id.isEmpty) return null;
    return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  }

  /// First 4 thumbnails used for the header collage
  List<String> get _headerThumbnails => _tracks
      .take(4)
      .map((t) => _ytThumb(t.url) ?? t.thumbnail)
      .whereType<String>()
      .toList();

  @override
  Widget build(BuildContext context) {
    final pl = widget.playlist;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────
          _Header(
            playlist:   pl,
            trackCount: _tracks.length,
            thumbnails: _headerThumbnails,
          ),

          // ── Action buttons ───────────────────────────────────────────
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

          // ── Track list ───────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorState(error: _error!, onRetry: _fetchTracks)
                    : _tracks.isEmpty
                        ? Center(
                            child: Text('No tracks found',
                                style: tt.bodyMedium))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 100),
                            itemCount: _tracks.length,
                            itemBuilder: (ctx, i) {
                              final result = _tracks[i];
                              return Consumer<DownloadProvider>(
                                builder: (ctx, dl, _) {
                                  // Find any job for this track by title
                                  DownloadJob? job;
                                  for (final j in dl.jobs) {
                                    if (j.title == result.title) {
                                      job = j;
                                      break;
                                    }
                                  }
                                  final isDone = job?.status == DownloadStatus.done;
                                  final isDownloading = job?.status == DownloadStatus.downloading;
                                  return _TrackRow(
                                    index:            i + 1,
                                    result:           result,
                                    isStreaming:      _streaming.contains(result.id),
                                    isDownloaded:     isDone || _downloaded.contains(result.id),
                                    downloadProgress: isDownloading ? job!.progress : null,
                                    onStream:         () => _streamTrack(result),
                                    onDownload:       () => _downloadTrack(result),
                                    onOptions:        () => TrackOptionsSheet.show(ctx, result),
                                  );
                                },
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

// ── Header with collage ───────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final FeaturedPlaylist playlist;
  final int trackCount;
  final List<String> thumbnails;

  const _Header({
    required this.playlist,
    required this.trackCount,
    required this.thumbnails,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pl = playlist;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            pl.gradient.first,
            pl.gradient.last.withOpacity(0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Back button
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Collage + info row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Row(
                children: [
                  // Collage square
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
                              : _EmojiBox(emoji: pl.emoji, gradient: pl.gradient),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Title / subtitle / count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pl.title,
                            style: tt.headlineMedium?.copyWith(
                                color: Colors.white, fontSize: 22)),
                        const SizedBox(height: 4),
                        Text(pl.subtitle,
                            style: tt.bodyMedium
                                ?.copyWith(color: Colors.white70)),
                        if (trackCount > 0) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('$trackCount tracks',
                                style: tt.labelSmall
                                    ?.copyWith(color: Colors.white)),
                          ),
                        ],
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

class _EmojiBox extends StatelessWidget {
  final String emoji;
  final List<Color> gradient;
  const _EmojiBox({required this.emoji, required this.gradient});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 40)),
      ),
    );
  }
}

// ── Track row ─────────────────────────────────────────────────────────────────

class _TrackRow extends StatelessWidget {
  final int index;
  final SearchResult result;
  final bool isStreaming;
  final bool isDownloaded;
  final double? downloadProgress; // null = idle, 0.0–1.0 = in progress
  final VoidCallback onStream;
  final VoidCallback onDownload;
  final VoidCallback onOptions;

  const _TrackRow({
    required this.index,
    required this.result,
    required this.isStreaming,
    required this.isDownloaded,
    this.downloadProgress,
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
            child: Builder(builder: (context) {
              final thumb = () {
                final id = Uri.tryParse(result.url)?.queryParameters['v'];
                if (id != null && id.isNotEmpty) {
                  return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
                }
                return result.thumbnail;
              }();
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
        '${result.uploader}${result.durationLabel.isNotEmpty ? ' • ${result.durationLabel}' : ''}',
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
          // Download button — three states: idle / downloading / done
          if (isDownloaded)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.check_circle, color: Colors.green, size: 22),
            )
          else if (downloadProgress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: downloadProgress,
                      strokeWidth: 2.5,
                      backgroundColor: cs.onSurface.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                    Text(
                      '${((downloadProgress ?? 0) * 100).toInt()}%',
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            IconButton(
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

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

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

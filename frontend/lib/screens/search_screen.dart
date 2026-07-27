import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/search_result.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../providers/server_provider.dart';
import '../screens/player_screen.dart';
import '../widgets/featured_playlists_section.dart';
import '../widgets/mini_player.dart';
import '../widgets/recently_played_section.dart';   // ← NEW
import '../widgets/server_status_badge.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl      = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  bool _searchActive = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String val) {
    setState(() => _searchActive = val.trim().isNotEmpty);
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      context.read<SearchProvider>().clear();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final server = context.read<ServerProvider>();
      if (!server.isOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server is offline')),
        );
        return;
      }
      context.read<SearchProvider>().search(val, server.serverUrl);
    });
  }

  void _clearSearch() {
    _ctrl.clear();
    context.read<SearchProvider>().clear();
    setState(() => _searchActive = false);
    _focusNode.unfocus();
  }

  void _download(SearchResult result) {
    final server = context.read<ServerProvider>();
    context.read<DownloadProvider>().enqueue(
          result.url,
          server.downloadUrl(result.url),
          title: result.title,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading: ${result.title}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _stream(SearchResult result) async {
    final server = context.read<ServerProvider>();
    final player = context.read<PlayerProvider>();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Loading stream…'),
          duration: Duration(seconds: 2)),
    );

    try {
      final res = await Dio().get(
        server.streamInfoUrl(result.url),
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      final data = res.data as Map<String, dynamic>;
      final st = StreamTrack(
        youtubeUrl:   result.url,
       streamUrl: data['stream_url'] as String,
        title:        data['title']     as String? ?? result.title,
        artist:       data['artist']    as String? ?? result.uploader,
        thumbnailUrl: data['thumbnail'] as String?,
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

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Text('Search', style: tt.headlineMedium),
                const Spacer(),
                const ServerStatusBadge(),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Find music on YouTube', style: tt.bodyMedium),
          ),
          const SizedBox(height: 14),

          // ── Search input ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              autofocus: false,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _onChanged,
              decoration: InputDecoration(
                hintText: 'Artist, song, album…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchActive
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _clearSearch,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Body: featured playlists OR search results ─────────────────
          Expanded(
            child: _searchActive
                ? _SearchResults(onDownload: _download, onStream: _stream)
                : _BrowseView(),
          ),

          const MiniPlayer(),
        ],
      ),
    );
  }
}

// ── Browse view ───────────────────────────────────────────────────────────────

class _BrowseView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          RecentlyPlayedSection(),   // ← NEW: shows above featured playlists
          FeaturedPlaylistsSection(),
        ],
      ),
    );
  }
}

// ── Search results ────────────────────────────────────────────────────────────

class _SearchResults extends StatelessWidget {
  final void Function(SearchResult) onDownload;
  final Future<void> Function(SearchResult) onStream;

  const _SearchResults(
      {required this.onDownload, required this.onStream});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Consumer<SearchProvider>(
      builder: (ctx, sp, _) {
        return switch (sp.state) {
          SearchState.idle => _hint(tt, cs),
          SearchState.loading =>
            const Center(child: CircularProgressIndicator()),
          SearchState.error => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded,
                        size: 40, color: cs.error.withOpacity(0.6)),
                    const SizedBox(height: 12),
                    Text(sp.error,
                        style: tt.bodyMedium?.copyWith(color: cs.error),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          SearchState.done when sp.results.isEmpty =>
            Center(child: Text('No results found', style: tt.bodyMedium)),
          SearchState.done => ListView.separated(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: sp.results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) => _ResultTile(
                result: sp.results[i],
                onDownload: () => onDownload(sp.results[i]),
                onStream: () => onStream(sp.results[i]),
              ),
            ),
        };
      },
    );
  }

  Widget _hint(TextTheme tt, ColorScheme cs) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.youtube_searched_for_rounded,
                size: 56, color: cs.onSurface.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text('Search YouTube', style: tt.bodyMedium),
            const SizedBox(height: 4),
            Text('Stream instantly or download as 320 kbps MP3',
                style: tt.labelSmall),
          ],
        ),
      );
}

// ── Result tile ───────────────────────────────────────────────────────────────

class _ResultTile extends StatefulWidget {
  final SearchResult result;
  final VoidCallback onDownload;
  final VoidCallback onStream;

  const _ResultTile(
      {required this.result, required this.onDownload, required this.onStream});

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile> {
  bool _queued = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r  = widget.result;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: r.thumbnail != null
            ? CachedNetworkImage(
                imageUrl: r.thumbnail!,
                width: 72,
                height: 48,
                fit: BoxFit.cover,
                placeholder: (_, __) => _placeholder(cs),
                errorWidget: (_, __, ___) => _placeholder(cs),
              )
            : _placeholder(cs),
      ),
      title: Text(r.title,
          style: tt.titleMedium?.copyWith(fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${r.uploader}${r.durationLabel.isNotEmpty ? ' • ${r.durationLabel}' : ''}',
        style: tt.bodyMedium?.copyWith(fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.play_circle_outline_rounded,
                color: cs.secondary, size: 24),
            tooltip: 'Stream',
            onPressed: widget.onStream,
          ),
          if (_queued)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.check_circle, color: Colors.green, size: 22),
            )
          else
            IconButton(
              icon: Icon(Icons.download_outlined,
                  color: cs.primary, size: 22),
              tooltip: 'Download',
              onPressed: () {
                widget.onDownload();
                setState(() => _queued = true);
              },
            ),
        ],
      ),
      onTap: widget.onStream,
    );
  }

  Widget _placeholder(ColorScheme cs) => Container(
        width: 72,
        height: 48,
        color: cs.surface,
        child: Icon(Icons.music_video_outlined,
            size: 20, color: cs.onSurface.withOpacity(0.3)),
      );
}

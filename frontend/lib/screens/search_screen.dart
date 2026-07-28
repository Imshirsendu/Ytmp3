import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/search_result.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/search_provider.dart';
import '../providers/server_provider.dart';
import '../screens/player_screen.dart';
import '../screens/yt_playlist_screen.dart';
import '../widgets/featured_playlists_section.dart';
import '../widgets/mini_player.dart';
import '../widgets/recently_played_section.dart';
import '../widgets/server_status_badge.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl      = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  bool _searchActive = false;

  late final TabController _tabCtrl;

  // ── Playlist search state ────────────────────────────────────────────────
  final _dio                           = Dio();
  List<YtPlaylistResult> _playlists    = [];
  bool   _playlistLoading              = false;
  String? _playlistError;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    setState(() => _searchActive = val.trim().isNotEmpty);
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      context.read<SearchProvider>().clear();
      setState(() {
        _playlists      = [];
        _playlistError  = null;
        _playlistLoading = false;
      });
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
      // Fire both searches in parallel
      context.read<SearchProvider>().search(val, server.serverUrl);
      _searchPlaylists(val, server.serverUrl);
    });
  }

  Future<void> _searchPlaylists(String query, String serverUrl) async {
    setState(() { _playlistLoading = true; _playlistError = null; });
    try {
      final res = await _dio.get(
        '$serverUrl/search',
        queryParameters: {
          'q':     '$query playlist',
          'limit': 20,
        },
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      final raw = res.data['results'] as List? ?? [];
      setState(() {
        _playlists = raw
            .map((e) => YtPlaylistResult.fromJson(e as Map<String, dynamic>))
            .where((p) => p.id.isNotEmpty)
            .toList();
        _playlistLoading = false;
      });
    } catch (e) {
      setState(() {
        _playlistLoading = false;
        _playlistError   = e.toString();
      });
    }
  }

  void _clearSearch() {
    _ctrl.clear();
    context.read<SearchProvider>().clear();
    setState(() {
      _searchActive    = false;
      _playlists       = [];
      _playlistError   = null;
      _playlistLoading = false;
    });
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
        options: Options(receiveTimeout: const Duration(seconds: 45)),
      );
      final raw  = res.data;
      final data = (raw is Map<String, dynamic>)
          ? raw
          : jsonDecode(raw as String) as Map<String, dynamic>;
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
          const SizedBox(height: 8),

          // ── Tabs (only visible when search is active) ─────────────────
          if (_searchActive)
            TabBar(
              controller: _tabCtrl,
              tabs: const [
                Tab(text: 'Songs'),
                Tab(text: 'Playlists'),
              ],
              labelStyle: tt.labelLarge,
              indicatorColor: cs.primary,
              dividerColor: Colors.transparent,
            ),

          // ── Body ──────────────────────────────────────────────────────
          Expanded(
            child: _searchActive
                ? TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // Tab 0 — Songs
                      _SearchResults(onDownload: _download, onStream: _stream),
                      // Tab 1 — Playlists
                      _PlaylistResults(
                        loading:   _playlistLoading,
                        error:     _playlistError,
                        playlists: _playlists,
                      ),
                    ],
                  )
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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RecentlyPlayedSection(),
          // ── YouTube Playlist Search promo card ───────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Search Playlists', style: tt.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Material(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  // Focus the search bar and switch to playlists tab
                  // The user just needs to type — tabs appear automatically
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.queue_music_rounded,
                          color: cs.primary, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Find YouTube Playlists',
                                style: tt.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              'Type in the search bar above → tap Playlists tab',
                              style: tt.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.55)),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: cs.onSurface.withOpacity(0.3)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const FeaturedPlaylistsSection(),
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

  void _showAddToPlaylist(BuildContext context) {
    final r  = widget.result;
    final pp = context.read<PlaylistProvider>();
    final ytId = Uri.tryParse(r.url)?.queryParameters['v'];
    final thumb = (ytId != null && ytId.isNotEmpty)
        ? 'https://i.ytimg.com/vi/$ytId/hqdefault.jpg'
        : r.thumbnail;
    final item = PlaylistItem.stream(
      url: r.url,
      trackTitle: r.title,
      trackArtist: r.uploader,
      thumb: thumb,
    );
    _SearchAddToPlaylistSheet.show(context, pp, item);
  }

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
        child: Builder(builder: (_) {
          final id = Uri.tryParse(r.url)?.queryParameters['v'];
          final thumb = (id != null && id.isNotEmpty)
              ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg'
              : r.thumbnail;
          return thumb != null
              ? CachedNetworkImage(
                  imageUrl: thumb,
                  width: 72,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _placeholder(cs),
                  errorWidget: (_, __, ___) => _placeholder(cs),
                )
              : _placeholder(cs);
        }),
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
          IconButton(
            icon: Icon(Icons.playlist_add_rounded,
                color: cs.onSurface.withOpacity(0.6), size: 22),
            tooltip: 'Add to playlist',
            onPressed: () => _showAddToPlaylist(context),
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
// ── Playlist search results ───────────────────────────────────────────────────

class _PlaylistResults extends StatelessWidget {
  final bool                   loading;
  final String?                error;
  final List<YtPlaylistResult> playlists;

  const _PlaylistResults({
    required this.loading,
    required this.error,
    required this.playlists,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded,
                  size: 40, color: cs.error.withOpacity(0.6)),
              const SizedBox(height: 12),
              Text(error!,
                  style: tt.bodyMedium?.copyWith(color: cs.error),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_play_rounded,
                size: 56, color: cs.onSurface.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text('No playlists found', style: tt.bodyMedium),
            const SizedBox(height: 4),
            Text('Try a different search term', style: tt.labelSmall),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: playlists.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) => _PlaylistTile(playlist: playlists[i]),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final YtPlaylistResult playlist;
  const _PlaylistTile({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final pl = playlist;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: pl.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: pl.thumbnailUrl!,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                placeholder: (_, __) => _thumb(cs),
                errorWidget: (_, __, ___) => _thumb(cs),
              )
            : _thumb(cs),
      ),
      title: Text(pl.title,
          style: tt.titleMedium?.copyWith(fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${pl.channelName}'
        '${pl.videoCount != null ? ' • ${pl.videoCount} videos' : ''}',
        style: tt.bodyMedium?.copyWith(fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.chevron_right_rounded,
          color: cs.onSurface.withOpacity(0.4)),
      onTap: () => YtPlaylistScreen.show(context, pl),
    );
  }

  Widget _thumb(ColorScheme cs) => Container(
        width: 64,
        height: 64,
        color: cs.surface,
        child: Icon(Icons.queue_music_rounded,
            size: 28, color: cs.onSurface.withOpacity(0.3)),
      );
}

// ── Add-to-playlist sheet (search context) ───────────────────────────────────

class _SearchAddToPlaylistSheet extends StatelessWidget {
  final PlaylistProvider pp;
  final PlaylistItem item;

  const _SearchAddToPlaylistSheet(
      {required this.pp, required this.item});

  static void show(
      BuildContext context, PlaylistProvider pp, PlaylistItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider.value(
        value: pp,
        child: _SearchAddToPlaylistSheet(pp: pp, item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final tt        = Theme.of(context).textTheme;
    final livepp    = context.watch<PlaylistProvider>();
    final playlists = livepp.playlists;

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
          if (playlists.isEmpty)
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
                itemCount: playlists.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final pl      = playlists[i];
                  final already = livepp.isInPlaylist(pl.id, item.id);
                  return ListTile(
                    leading: Icon(Icons.queue_music_rounded,
                        color: already
                            ? cs.primary
                            : cs.onSurface.withOpacity(0.5)),
                    title: Text(pl.name, style: tt.titleMedium),
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
                                        overflow: TextOverflow.ellipsis)),
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
          decoration: const InputDecoration(hintText: 'Playlist name'),
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

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../screens/player_screen.dart';
import '../screens/playlist_detail_screen.dart';
import '../widgets/cover_art.dart';
import '../widgets/mini_player.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Consumer<LibraryProvider>(
        builder: (ctx, lib, _) {
          final tracks = lib.tracks;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Text('Library', style: tt.headlineMedium),
                    const Spacer(),
                    IconButton(
                      onPressed: lib.refresh,
                      icon: lib.loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_outlined),
                    ),
                    PopupMenuButton<SortOrder>(
                      icon: const Icon(Icons.sort_outlined),
                      onSelected: lib.setSortOrder,
                      itemBuilder: (_) => [
                        _sortItem(SortOrder.dateAdded, 'Date Added',
                            lib.sortOrder),
                        _sortItem(SortOrder.title, 'Title', lib.sortOrder),
                        _sortItem(SortOrder.artist, 'Artist', lib.sortOrder),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Search ──────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: TextField(
                  onChanged: lib.setSearch,
                  decoration: InputDecoration(
                    hintText: 'Search tracks…',
                    prefixIcon:
                        const Icon(Icons.search_outlined, size: 18),
                    suffixIcon: lib.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => lib.setSearch(''),
                          )
                        : null,
                  ),
                ),
              ),

              // ── Playlists row ────────────────────────────────────────
              _PlaylistsRow(allTracks: tracks),

              // ── Track count ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  '${tracks.length} track${tracks.length == 1 ? '' : 's'}',
                  style: tt.labelSmall,
                ),
              ),

              // ── Track list ───────────────────────────────────────────
              Expanded(
                child: tracks.isEmpty
                    ? _emptyState(lib.loading, tt, cs)
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: tracks.length,
                        itemBuilder: (ctx, i) => _TrackTile(
                          track: tracks[i],
                          allTracks: tracks,
                          index: i,
                          onDelete: () => lib.deleteTrack(tracks[i]),
                        ),
                      ),
              ),

              // ── Mini player ──────────────────────────────────────────
              const MiniPlayer(),
            ],
          );
        },
      ),
    );
  }

  PopupMenuItem<SortOrder> _sortItem(
      SortOrder value, String label, SortOrder current) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Text(label),
        const Spacer(),
        if (value == current) const Icon(Icons.check, size: 16),
      ]),
    );
  }

  Widget _emptyState(bool loading, TextTheme tt, ColorScheme cs) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music_outlined,
              size: 56, color: cs.onSurface.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text('No tracks yet', style: tt.bodyMedium),
          const SizedBox(height: 4),
          Text('Download something first', style: tt.labelSmall),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Playlists horizontal row
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistsRow extends StatelessWidget {
  final List<Track> allTracks;
  const _PlaylistsRow({required this.allTracks});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Consumer<PlaylistProvider>(
      builder: (ctx, pp, _) {
        final playlists = pp.playlists;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Text('Playlists', style: tt.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _createPlaylist(context, pp),
                    icon: Icon(Icons.add, size: 16, color: cs.primary),
                    label: Text('New',
                        style: TextStyle(color: cs.primary, fontSize: 12)),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4)),
                  ),
                ],
              ),
            ),
            if (playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('No playlists yet — tap New to create one',
                    style: tt.labelSmall),
              )
            else
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: playlists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    final pl = playlists[i];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaylistDetailScreen(
                              playlist: pl, allTracks: allTracks),
                        ),
                      ),
                      child: Container(
                        width: 140,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16213E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.queue_music_outlined,
                                color: cs.primary, size: 22),
                            const SizedBox(height: 6),
                            Text(pl.name,
                                style: tt.titleMedium?.copyWith(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(
                                '${pl.trackPaths.length} track${pl.trackPaths.length == 1 ? '' : 's'}',
                                style: tt.labelSmall),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _createPlaylist(
      BuildContext context, PlaylistProvider pp) async {
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
    if (name != null && name.isNotEmpty) {
      await pp.createPlaylist(name);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Track tile with slidable actions
// ─────────────────────────────────────────────────────────────────────────────

class _TrackTile extends StatelessWidget {
  final Track track;
  final List<Track> allTracks;
  final int index;
  final VoidCallback onDelete;

  const _TrackTile({
    required this.track,
    required this.allTracks,
    required this.index,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final player = context.read<PlayerProvider>();

    return Slidable(
      key: ValueKey(track.filePath),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _addToPlaylist(context),
            backgroundColor: cs.primary,
            foregroundColor: Colors.white,
            icon: Icons.playlist_add,
            label: 'Add',
          ),
          SlidableAction(
            onPressed: (_) => _confirmDelete(context),
            backgroundColor: Colors.red.shade800,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Delete',
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CoverArt(coverArtBytes: track.coverArt, size: 48),
        title: Text(track.title,
            style: tt.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text('${track.artist} • ${_fmt(track.duration)}',
            style: tt.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        onTap: () async {
          await player.playAll(allTracks, startIndex: index);
          if (context.mounted) PlayerScreen.show(context);
        },
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  Future<void> _addToPlaylist(BuildContext context) async {
    final pp = context.read<PlaylistProvider>();
    final playlists = pp.playlists;

    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a playlist first')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Add to playlist',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
          ...playlists.map((pl) => ListTile(
                leading: const Icon(Icons.queue_music_outlined,
                    color: Color(0xFF6C63FF)),
                title: Text(pl.name,
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text('${pl.trackPaths.length} tracks',
                    style: const TextStyle(color: Color(0xFF9090B0))),
                onTap: () => Navigator.pop(context, pl.id),
              )),
          const SizedBox(height: 16),
        ],
      ),
    );

    if (chosen != null) {
      await pp.addTrack(chosen, track);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added to playlist')),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete track?'),
        content: Text('This will permanently delete "${track.title}"'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) onDelete();
  }
}

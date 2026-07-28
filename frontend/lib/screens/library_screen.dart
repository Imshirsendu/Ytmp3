import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../screens/player_screen.dart';
import '../screens/playlist_detail_screen.dart';
import '../screens/settings_screen.dart';
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

  // ── Multi-select state ────────────────────────────────────────────────────
  final Set<String> _selected = {}; // file paths
  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelect(String filePath) {
    setState(() {
      if (_selected.contains(filePath)) {
        _selected.remove(filePath);
      } else {
        _selected.add(filePath);
      }
    });
  }

  void _clearSelection() => setState(() => _selected.clear());

  void _selectAll(List<Track> tracks) {
    setState(() => _selected
      ..clear()
      ..addAll(tracks.map((t) => t.filePath)));
  }

  // ── Toolbar actions ───────────────────────────────────────────────────────

  Future<void> _playSelected(
      BuildContext context, List<Track> allTracks) async {
    final toPlay = allTracks
        .where((t) => _selected.contains(t.filePath))
        .toList();
    if (toPlay.isEmpty) return;
    final player = context.read<PlayerProvider>();
    await player.playAll(toPlay, startIndex: 0);
    _clearSelection();
    if (context.mounted) PlayerScreen.show(context);
  }

  Future<void> _deleteSelected(
      BuildContext context, LibraryProvider lib) async {
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete tracks?'),
        content: Text(
            'This will permanently delete $count track${count == 1 ? '' : 's'}.'),
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
    if (confirm != true) return;
    final paths = Set<String>.from(_selected);
    _clearSelection();
    for (final t in lib.tracks.where((t) => paths.contains(t.filePath))) {
      await lib.deleteTrack(t);
    }
  }

  Future<void> _addSelectedToPlaylist(
      BuildContext context, List<Track> allTracks) async {
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Add ${_selected.length} track${_selected.length == 1 ? '' : 's'} to…',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
          ...playlists.map((pl) => ListTile(
                leading: const Icon(Icons.queue_music_outlined,
                    color: Color(0xFF6C63FF)),
                title: Text(pl.name,
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text('${pl.items.length} items',
                    style: const TextStyle(color: Color(0xFF9090B0))),
                onTap: () => Navigator.pop(context, pl.id),
              )),
          const SizedBox(height: 16),
        ],
      ),
    );

    if (chosen == null) return;

    final toAdd = allTracks
        .where((t) => _selected.contains(t.filePath))
        .toList();
    for (final t in toAdd) {
      await pp.addTrack(chosen, t);
    }

    _clearSelection();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${toAdd.length} track${toAdd.length == 1 ? '' : 's'} to playlist')),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
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

              // ── Header ────────────────────────────────────────────────
              _selecting
                  ? _SelectionHeader(
                      count: _selected.length,
                      total: tracks.length,
                      onClear: _clearSelection,
                      onSelectAll: () => _selectAll(tracks),
                      onPlay: () => _playSelected(context, tracks),
                      onDelete: () => _deleteSelected(context, lib),
                      onAddToPlaylist: () =>
                          _addSelectedToPlaylist(context, tracks),
                    )
                  : Padding(
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
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh_outlined),
                          ),
                          PopupMenuButton<SortOrder>(
                            icon: const Icon(Icons.sort_outlined),
                            onSelected: lib.setSortOrder,
                            itemBuilder: (_) => [
                              _sortItem(SortOrder.dateAdded, 'Date Added',
                                  lib.sortOrder),
                              _sortItem(
                                  SortOrder.title, 'Title', lib.sortOrder),
                              _sortItem(
                                  SortOrder.artist, 'Artist', lib.sortOrder),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined),
                            tooltip: 'Settings',
                            onPressed: () => SettingsScreen.show(context),
                          ),
                        ],
                      ),
                    ),

              // ── Search (hidden in select mode) ────────────────────────
              if (!_selecting)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
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

              // ── Playlists row (hidden in select mode) ─────────────────
              if (!_selecting) _PlaylistsRow(allTracks: tracks),

              // ── Track count ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  _selecting
                      ? '${_selected.length} selected'
                      : '${tracks.length} track${tracks.length == 1 ? '' : 's'}',
                  style: tt.labelSmall,
                ),
              ),

              // ── Track list ────────────────────────────────────────────
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
                          // Multi-select
                          selecting: _selecting,
                          selected:
                              _selected.contains(tracks[i].filePath),
                          onLongPress: () =>
                              _toggleSelect(tracks[i].filePath),
                          onSelectTap: () =>
                              _toggleSelect(tracks[i].filePath),
                        ),
                      ),
              ),

              // ── Mini player ───────────────────────────────────────────
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
// Selection-mode header bar
// ─────────────────────────────────────────────────────────────────────────────

class _SelectionHeader extends StatelessWidget {
  final int count;
  final int total;
  final VoidCallback onClear;
  final VoidCallback onSelectAll;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onAddToPlaylist;

  const _SelectionHeader({
    required this.count,
    required this.total,
    required this.onClear,
    required this.onSelectAll,
    required this.onPlay,
    required this.onDelete,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      color: cs.primary.withOpacity(0.08),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: onClear,
            tooltip: 'Cancel selection',
          ),
          Text(
            '$count selected',
            style: tt.titleMedium?.copyWith(color: cs.primary),
          ),
          const Spacer(),
          // Select all
          TextButton(
            onPressed: onSelectAll,
            child: Text(
              'All',
              style: TextStyle(color: cs.primary, fontSize: 13),
            ),
          ),
          // Play selected
          IconButton(
            icon: Icon(Icons.play_arrow_rounded, color: cs.primary),
            tooltip: 'Play selected',
            onPressed: count > 0 ? onPlay : null,
          ),
          // Add to playlist
          IconButton(
            icon: Icon(Icons.playlist_add_rounded,
                color: cs.onSurface.withOpacity(0.7)),
            tooltip: 'Add to playlist',
            onPressed: count > 0 ? onAddToPlaylist : null,
          ),
          // Delete
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: Colors.red.shade400),
            tooltip: 'Delete selected',
            onPressed: count > 0 ? onDelete : null,
          ),
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
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: playlists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    final pl = playlists[i];
                    final firstItem =
                        pl.items.isNotEmpty ? pl.items.first : null;
                    final thumbUrl = firstItem?.isStream == true
                        ? (_ytThumb(firstItem!.youtubeUrl) ??
                            firstItem.thumbnailUrl)
                        : null;
                    final localThumb = firstItem?.isStream == false
                        ? allTracks
                            .where((t) =>
                                t.filePath == firstItem!.filePath)
                            .firstOrNull
                            ?.coverArt
                        : null;

                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PlaylistDetailScreen(playlist: pl),
                        ),
                      ),
                      child: Container(
                        width: 140,
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 56,
                              width: 140,
                              child: thumbUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: thumbUrl,
                                      fit: BoxFit.cover,
                                      width: 140,
                                      height: 56,
                                      errorWidget: (_, __, ___) =>
                                          _thumbFallback(cs),
                                    )
                                  : localThumb != null
                                      ? Image.memory(localThumb,
                                          fit: BoxFit.cover,
                                          width: 140,
                                          height: 56)
                                      : _thumbFallback(cs),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(8, 5, 8, 6),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(pl.name,
                                      style: tt.titleMedium
                                          ?.copyWith(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text(
                                      '${pl.items.length} item${pl.items.length == 1 ? '' : 's'}',
                                      style: tt.labelSmall),
                                ],
                              ),
                            ),
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

  Widget _thumbFallback(ColorScheme cs) => Container(
        color: cs.surface,
        child: Icon(Icons.queue_music_outlined,
            size: 22, color: cs.primary.withOpacity(0.5)),
      );

  String? _ytThumb(String? youtubeUrl) {
    if (youtubeUrl == null) return null;
    final id = Uri.tryParse(youtubeUrl)?.queryParameters['v'];
    if (id == null || id.isEmpty) return null;
    return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
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
// Track tile — normal + select mode
// ─────────────────────────────────────────────────────────────────────────────

class _TrackTile extends StatelessWidget {
  final Track track;
  final List<Track> allTracks;
  final int index;
  final VoidCallback onDelete;

  // Multi-select
  final bool selecting;
  final bool selected;
  final VoidCallback onLongPress;
  final VoidCallback onSelectTap;

  const _TrackTile({
    required this.track,
    required this.allTracks,
    required this.index,
    required this.onDelete,
    required this.selecting,
    required this.selected,
    required this.onLongPress,
    required this.onSelectTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final player = context.read<PlayerProvider>();

    // In select mode — disable Slidable, show checkbox
    if (selecting) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: selected
            ? cs.primary.withOpacity(0.1)
            : Colors.transparent,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CoverArt(coverArtBytes: track.coverArt, size: 48),
              if (selected)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.check_rounded,
                      color: cs.onPrimary, size: 24),
                ),
            ],
          ),
          title: Text(track.title,
              style: tt.titleMedium?.copyWith(
                color: selected ? cs.primary : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          subtitle: Text('${track.artist} • ${_fmt(track.duration)}',
              style: tt.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          onTap: onSelectTap,
          onLongPress: onSelectTap,
        ),
      );
    }

    // Normal mode — slidable
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
        onLongPress: onLongPress, // enters select mode
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
                subtitle: Text('${pl.items.length} items',
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
          const SnackBar(content: Text('Added to playlist')),
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

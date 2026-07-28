import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

enum SortOrder { dateAdded, title, artist }

class LibraryProvider extends ChangeNotifier {
  List<Track> _allTracks   = [];
  List<Track> _filtered    = [];
  bool        _loading     = false;
  SortOrder   _sortOrder   = SortOrder.dateAdded;
  String      _searchQuery = '';

  List<Track> get tracks      => _filtered;
  bool        get loading     => _loading;
  SortOrder   get sortOrder   => _sortOrder;
  String      get searchQuery => _searchQuery;
  Map<String, Track> get trackMap =>
      { for (final t in _allTracks) t.filePath: t };

  LibraryProvider() {
    refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final dir = await _musicDir();
      if (dir == null || !dir.existsSync()) {
        _allTracks = [];
      } else {
        final files = dir
            .listSync(recursive: false)
            .whereType<File>()
            .where((f) => f.path.endsWith('.mp3'))
            .toList();

        final tracks = <Track>[];
        for (final f in files) {
          try {
            final stat  = f.statSync();
            final name  = f.path.split('/').last.split('\\').last;
            final title = name.endsWith('.mp3')
                ? name.substring(0, name.length - 4)
                : name;
            tracks.add(Track(
              id:        f.path,
              filePath:  f.path,
              title:     title,
              artist:    'Unknown Artist',
              album:     'YT-MP3',
              duration:  Duration.zero,
              dateAdded: stat.modified,
              coverArt:  null,
            ));
          } catch (_) {}
        }
        _allTracks = tracks;
      }
    } catch (e) {
      debugPrint('LibraryProvider refresh error: $e');
      _allTracks = [];
    }
    _loading = false;
    _applyFilterAndSort();
  }

  void setSortOrder(SortOrder order) {
    _sortOrder = order;
    _applyFilterAndSort();
  }

  void setSearch(String query) {
    _searchQuery = query;
    _applyFilterAndSort();
  }

  Future<void> deleteTrack(Track track) async {
    try {
      final f = File(track.filePath);
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      debugPrint('LibraryProvider deleteTrack error: $e');
    }
    _allTracks.removeWhere((t) => t.filePath == track.filePath);
    _applyFilterAndSort();
  }

  void _applyFilterAndSort() {
    var list = List<Track>.from(_allTracks);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) =>
          t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q)).toList();
    }

    switch (_sortOrder) {
      case SortOrder.dateAdded:
        list.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
      case SortOrder.title:
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
      case SortOrder.artist:
        list.sort((a, b) => a.artist.compareTo(b.artist));
        break;
    }

    _filtered = list;
    notifyListeners();
  }

  Future<Directory?> _musicDir() async {
    try {
      if (Platform.isAndroid) {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final parts = ext.path.split('/');
          final androidIdx = parts.indexOf('Android');
          final sdcard = androidIdx > 0
              ? parts.sublist(0, androidIdx).join('/')
              : ext.path;
          return Directory('$sdcard/Music/YT-MP3');
        }
      }
      final base = await getApplicationDocumentsDirectory();
      return Directory('${base.path}/Music');
    } catch (_) {
      return null;
    }
  }
}

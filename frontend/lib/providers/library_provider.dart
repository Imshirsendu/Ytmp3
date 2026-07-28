import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:id3tag/id3tag.dart';
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
            final rawTitle = name.endsWith('.mp3')
                ? name.substring(0, name.length - 4)
                : name;

            // Read ID3 tags for real artist/duration
            String title  = rawTitle;
            String artist = 'Unknown Artist';
            Duration duration = Duration.zero;
            Uint8List? coverArt;

            try {
              final parser = ID3TagReader.path(f.path);
              final tag    = await parser.readTag();

              if (tag.title != null && tag.title!.isNotEmpty) {
                title = tag.title!;
              }
              if (tag.artist != null && tag.artist!.isNotEmpty) {
                artist = tag.artist!;
              }
              // id3tag exposes pictures; duration comes from audio header
              if (tag.pictures.isNotEmpty) {
                coverArt = Uint8List.fromList(tag.pictures.first.imageData);
              }
            } catch (_) {
              // Tag read failed — fall back to filename / unknowns
            }

            // Try to get duration from the audio pipeline length if available
            // id3tag doesn't expose duration directly; use file stat size as
            // a rough heuristic: assume ~128kbps = 16KB/s
            if (duration == Duration.zero) {
              try {
                final bytes   = f.lengthSync();
                final seconds = (bytes / 16000).round(); // rough 128kbps estimate
                if (seconds > 0) {
                  duration = Duration(seconds: seconds);
                }
              } catch (_) {}
            }

            tracks.add(Track(
              id:        f.path,
              filePath:  f.path,
              title:     title,
              artist:    artist,
              album:     'YT-MP3',
              duration:  duration,
              dateAdded: stat.modified,
              coverArt:  coverArt,
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

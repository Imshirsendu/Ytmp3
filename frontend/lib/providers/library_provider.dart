import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:id3tag/id3tag.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

export '../models/track.dart' show DownloadStatus, DownloadJob;

enum SortOrder { dateAdded, title, artist }

class LibraryProvider extends ChangeNotifier {
  List<Track> _tracks = [];
  String _searchQuery = '';
  SortOrder _sortOrder = SortOrder.dateAdded;
  bool _loading = false;

  List<Track> get tracks {
    var list = List<Track>.from(_tracks);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((t) =>
              t.title.toLowerCase().contains(q) ||
              t.artist.toLowerCase().contains(q) ||
              t.album.toLowerCase().contains(q))
          .toList();
    }

    switch (_sortOrder) {
      case SortOrder.dateAdded:
        list.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      case SortOrder.title:
        list.sort((a, b) => a.title.compareTo(b.title));
      case SortOrder.artist:
        list.sort((a, b) => a.artist.compareTo(b.artist));
    }

    return list;
  }

  /// Quick lookup map used by PlaylistProvider.resolveTracks
  Map<String, Track> get trackMap => {for (final t in _tracks) t.filePath: t};

  bool get loading => _loading;
  String get searchQuery => _searchQuery;
  SortOrder get sortOrder => _sortOrder;

  void setSearch(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setSortOrder(SortOrder order) {
    _sortOrder = order;
    notifyListeners();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();

    try {
      final dirs = await _allMusicDirs();
      final seen = <String>{};
      final tracks = <Track>[];

      for (final dir in dirs) {
        if (!dir.existsSync()) continue;
        final files = dir
            .listSync(recursive: true)   // recursive so sub-folders work too
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.mp3'))
            .toList();

        for (final file in files) {
          if (seen.contains(file.path)) continue;
          seen.add(file.path);
          final track = await _readTrack(file);
          if (track != null) tracks.add(track);
        }
      }

      _tracks = tracks;
    } catch (e) {
      debugPrint('LibraryProvider.refresh error: $e');
    }

    _loading = false;
    notifyListeners();
  }

  /// Returns all directories the library should scan.
  /// Covers: app-private folder, external /sdcard/Music/YT-MP3,
  /// and any other standard external storage location.
  Future<List<Directory>> _allMusicDirs() async {
    final dirs = <Directory>[];

    // 1. App-private documents folder (iOS + Android fallback)
    try {
      final base = await getApplicationDocumentsDirectory();
      dirs.add(Directory('${base.path}/Music'));
    } catch (_) {}

    if (Platform.isAndroid) {
      // 2. External storage → climb to /sdcard root → Music/YT-MP3
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final parts = ext.path.split('/');
          final androidIdx = parts.indexOf('Android');
          final sdcard = androidIdx > 0
              ? parts.sublist(0, androidIdx).join('/')
              : ext.path;
          dirs.add(Directory('$sdcard/Music/YT-MP3'));
          // Also scan the root Music folder so music added manually is visible
          dirs.add(Directory('$sdcard/Music'));
        }
      } catch (_) {}

      // 3. Fallback: well-known absolute paths on most Android ROMs
      for (final path in [
        '/storage/emulated/0/Music/YT-MP3',
        '/storage/emulated/0/Music',
        '/sdcard/Music/YT-MP3',
        '/sdcard/Music',
      ]) {
        final d = Directory(path);
        if (d.existsSync()) dirs.add(d);
      }
    }

    return dirs;
  }

  Future<Track?> _readTrack(File file) async {
    try {
      final stat = file.statSync();
      final parser = ID3TagReader.path(file.path);
      final tag = await parser.readTag();

      final title  = _nonEmpty(tag.title)  ?? _titleFromPath(file.path);
      final artist = _nonEmpty(tag.artist) ?? 'Unknown Artist';
      final album  = _nonEmpty(tag.album)  ?? 'Unknown Album';
      final duration = tag.duration ?? Duration.zero;

      Uint8List? coverArt;
      if (tag.pictures.isNotEmpty) {
        coverArt = Uint8List.fromList(tag.pictures.first.imageData);
      }

      return Track(
        id: file.path,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        filePath: file.path,
        dateAdded: stat.modified,
        coverArt: coverArt,
      );
    } catch (e) {
      debugPrint('Could not read track ${file.path}: $e');
      return null;
    }
  }

  String? _nonEmpty(String? s) =>
      (s != null && s.trim().isNotEmpty) ? s.trim() : null;

  String _titleFromPath(String path) {
    final name = path.split('/').last.split('\\').last;
    return name.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
  }

  Future<void> deleteTrack(Track track) async {
    try {
      await File(track.filePath).delete();
    } catch (_) {}
    _tracks.remove(track);
    notifyListeners();
  }
}

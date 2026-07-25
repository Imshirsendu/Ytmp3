import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

class Playlist {
  final String id;
  String name;
  List<String> trackPaths; // ordered list of file paths
  DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    required this.trackPaths,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackPaths': trackPaths,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String,
        trackPaths: List<String>.from(j['trackPaths'] as List),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class PlaylistProvider extends ChangeNotifier {
  static const _key = 'playlists_v1';

  List<Playlist> _playlists = [];
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  PlaylistProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _playlists = list.map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_playlists.map((p) => p.toJson()).toList()));
  }

  Future<Playlist> createPlaylist(String name) async {
    final pl = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      trackPaths: [],
      createdAt: DateTime.now(),
    );
    _playlists.add(pl);
    notifyListeners();
    await _save();
    return pl;
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final pl = _byId(id);
    if (pl == null) return;
    pl.name = newName;
    notifyListeners();
    await _save();
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((p) => p.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> addTrack(String playlistId, Track track) async {
    final pl = _byId(playlistId);
    if (pl == null) return;
    if (!pl.trackPaths.contains(track.filePath)) {
      pl.trackPaths.add(track.filePath);
      notifyListeners();
      await _save();
    }
  }

  Future<void> removeTrack(String playlistId, String filePath) async {
    final pl = _byId(playlistId);
    if (pl == null) return;
    pl.trackPaths.remove(filePath);
    notifyListeners();
    await _save();
  }

  Future<void> reorderTrack(String playlistId, int oldIndex, int newIndex) async {
    final pl = _byId(playlistId);
    if (pl == null) return;
    final item = pl.trackPaths.removeAt(oldIndex);
    pl.trackPaths.insert(newIndex, item);
    notifyListeners();
    await _save();
  }

  /// Returns the tracks of a playlist resolved against the library map.
  List<Track> resolveTracks(String playlistId, Map<String, Track> library) {
    final pl = _byId(playlistId);
    if (pl == null) return [];
    return pl.trackPaths
        .map((path) => library[path])
        .whereType<Track>()
        .toList();
  }

  Playlist? _byId(String id) {
    try {
      return _playlists.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}

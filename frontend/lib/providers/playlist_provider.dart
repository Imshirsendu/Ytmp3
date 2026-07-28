import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

// ── PlaylistItem ──────────────────────────────────────────────────────────────

/// A single item in a user playlist — either a local downloaded track
/// or an online stream (stored by YouTube URL).
class PlaylistItem {
  final bool isStream;

  // Local track fields
  final String? filePath;

  // Stream fields
  final String? youtubeUrl;
  final String? title;
  final String? artist;
  final String? thumbnailUrl;

  const PlaylistItem.local(String path)
      : isStream = false,
        filePath = path,
        youtubeUrl = null,
        title = null,
        artist = null,
        thumbnailUrl = null;

  const PlaylistItem.stream({
    required String url,
    required String trackTitle,
    required String trackArtist,
    String? thumb,
  })  : isStream = true,
        youtubeUrl = url,
        title = trackTitle,
        artist = trackArtist,
        thumbnailUrl = thumb,
        filePath = null;

  /// Stable unique key used for deduplication.
  String get id => isStream ? youtubeUrl! : filePath!;

  Map<String, dynamic> toJson() => {
        'isStream': isStream,
        'filePath': filePath,
        'youtubeUrl': youtubeUrl,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
      };

  factory PlaylistItem.fromJson(Map<String, dynamic> j) {
    final isStream = j['isStream'] as bool? ?? false;
    if (isStream) {
      return PlaylistItem.stream(
        url: j['youtubeUrl'] as String,
        trackTitle: j['title'] as String? ?? '',
        trackArtist: j['artist'] as String? ?? '',
        thumb: j['thumbnailUrl'] as String?,
      );
    }
    return PlaylistItem.local(j['filePath'] as String);
  }
}

// ── Playlist ──────────────────────────────────────────────────────────────────

class Playlist {
  final String id;
  String name;
  List<PlaylistItem> items;
  DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
  });

  /// Backwards-compatible: local-only paths (used by legacy code paths).
  List<String> get trackPaths =>
      items.where((i) => !i.isStream).map((i) => i.filePath!).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((i) => i.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Playlist.fromJson(Map<String, dynamic> j) {
    // Migration: old format stored trackPaths (List<String>), new stores items.
    List<PlaylistItem> items;
    if (j.containsKey('items')) {
      items = (j['items'] as List)
          .map((e) => PlaylistItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      // Legacy: convert old trackPaths list to local PlaylistItems.
      items = (j['trackPaths'] as List? ?? [])
          .cast<String>()
          .map((p) => PlaylistItem.local(p))
          .toList();
    }
    return Playlist(
      id: j['id'] as String,
      name: j['name'] as String,
      items: items,
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }
}

// ── PlaylistProvider ──────────────────────────────────────────────────────────

class PlaylistProvider extends ChangeNotifier {
  static const _key = 'playlists_v2'; // bumped key so old data is ignored cleanly

  List<Playlist> _playlists = [];
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  PlaylistProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // Try new key first, then fall back to legacy key for migration.
    final raw = prefs.getString(_key) ?? prefs.getString('playlists_v1');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _playlists = list
          .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_playlists.map((p) => p.toJson()).toList()));
  }

  Future<Playlist> createPlaylist(String name) async {
    final pl = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      items: [],
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

  // ── Item management ───────────────────────────────────────────────────────

  Future<void> addItem(String playlistId, PlaylistItem item) async {
    final pl = _byId(playlistId);
    if (pl == null) return;
    if (pl.items.any((i) => i.id == item.id)) return; // no duplicates
    pl.items.add(item);
    notifyListeners();
    await _save();
  }

  /// Convenience: add a local Track (backwards-compatible).
  Future<void> addTrack(String playlistId, Track track) =>
      addItem(playlistId, PlaylistItem.local(track.filePath));

  Future<void> removeItem(String playlistId, String itemId) async {
    final pl = _byId(playlistId);
    if (pl == null) return;
    pl.items.removeWhere((i) => i.id == itemId);
    notifyListeners();
    await _save();
  }

  /// Legacy method kept for any existing callers.
  Future<void> removeTrack(String playlistId, String filePath) =>
      removeItem(playlistId, filePath);

  Future<void> reorderItem(
      String playlistId, int oldIndex, int newIndex) async {
    final pl = _byId(playlistId);
    if (pl == null) return;
    final item = pl.items.removeAt(oldIndex);
    pl.items.insert(newIndex, item);
    notifyListeners();
    await _save();
  }

  /// Legacy method kept for any existing callers.
  Future<void> reorderTrack(
          String playlistId, int oldIndex, int newIndex) =>
      reorderItem(playlistId, oldIndex, newIndex);

  /// Returns local tracks of a playlist resolved against the library map.
  /// Stream items are skipped here — use [itemsOf] for the full list.
  List<Track> resolveTracks(String playlistId, Map<String, Track> library) {
    final pl = _byId(playlistId);
    if (pl == null) return [];
    return pl.items
        .where((i) => !i.isStream)
        .map((i) => library[i.filePath])
        .whereType<Track>()
        .toList();
  }

  /// Returns all items of a playlist (streams + locals).
  List<PlaylistItem> itemsOf(String playlistId) =>
      _byId(playlistId)?.items ?? [];

  /// Returns true if a given item id is in any playlist.
  bool isInPlaylist(String playlistId, String itemId) =>
      _byId(playlistId)?.items.any((i) => i.id == itemId) ?? false;

  Playlist? _byId(String id) {
    try {
      return _playlists.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}

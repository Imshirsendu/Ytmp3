import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// Represents a recently played entry — either a local track or a stream.
class RecentEntry {
  final String id;           // filePath for local, youtubeUrl for stream
  final String title;
  final String artist;
  final String? thumbnailUrl; // null for local tracks
  final bool isStream;
  final DateTime playedAt;

  const RecentEntry({
    required this.id,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.isStream,
    required this.playedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'isStream': isStream,
        'playedAt': playedAt.toIso8601String(),
      };

  factory RecentEntry.fromJson(Map<String, dynamic> j) => RecentEntry(
        id: j['id'] as String,
        title: j['title'] as String,
        artist: j['artist'] as String,
        thumbnailUrl: j['thumbnailUrl'] as String?,
        isStream: j['isStream'] as bool,
        playedAt: DateTime.parse(j['playedAt'] as String),
      );

  factory RecentEntry.fromTrack(Track t) => RecentEntry(
        id: t.filePath,
        title: t.title,
        artist: t.artist,
        isStream: false,
        playedAt: DateTime.now(),
      );

  factory RecentEntry.fromStream(StreamTrackInfo s) => RecentEntry(
        id: s.youtubeUrl,
        title: s.title,
        artist: s.artist,
        thumbnailUrl: s.thumbnailUrl,
        isStream: true,
        playedAt: DateTime.now(),
      );
}

/// Thin info bag so recently_played_provider doesn't depend on player_provider.
class StreamTrackInfo {
  final String youtubeUrl;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  const StreamTrackInfo({
    required this.youtubeUrl,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
  });
}

class RecentlyPlayedProvider extends ChangeNotifier {
  static const _key = 'recently_played_v1';
  static const _maxEntries = 10;

  List<RecentEntry> _entries = [];
  List<RecentEntry> get entries => List.unmodifiable(_entries);

  RecentlyPlayedProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => RecentEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _entries = list;
      notifyListeners();
    } catch (e) {
      debugPrint('RecentlyPlayedProvider load error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('RecentlyPlayedProvider save error: $e');
    }
  }

  Future<void> logTrack(Track track) async {
    _add(RecentEntry.fromTrack(track));
  }

  Future<void> logStream(StreamTrackInfo info) async {
    _add(RecentEntry.fromStream(info));
  }

  void _add(RecentEntry entry) {
    // Remove duplicate (same id) if already present
    _entries.removeWhere((e) => e.id == entry.id);
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries = _entries.sublist(0, _maxEntries);
    }
    notifyListeners();
    _save();
  }

  Future<void> clear() async {
    _entries = [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

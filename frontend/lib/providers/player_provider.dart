import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';

import '../models/search_result.dart';
import '../models/track.dart';
import 'recently_played_provider.dart';

// ── StreamTrack ──────────────────────────────────────────────────────────────

class StreamTrack {
  final String youtubeUrl;
  final String streamUrl;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final Duration duration;

  const StreamTrack({
    required this.youtubeUrl,
    required this.streamUrl,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.duration = Duration.zero,
  });
}

// ── NowPlaying ───────────────────────────────────────────────────────────────

class NowPlaying {
  final Track? local;
  final StreamTrack? stream;

  const NowPlaying.local(this.local) : stream = null;
  const NowPlaying.stream(this.stream) : local = null;

  String get title  => local?.title  ?? stream?.title  ?? '';
  String get artist => local?.artist ?? stream?.artist ?? '';
  bool   get isStream => stream != null;
}

// ── LoopMode ─────────────────────────────────────────────────────────────────

enum AppLoopMode { none, one, all }

// ── PlayerProvider ───────────────────────────────────────────────────────────

class PlayerProvider extends ChangeNotifier {
  final _player = AudioPlayer();
  final _rng    = Random();

  NowPlaying? _current;

  // Local queue (Track objects)
  List<Track> _queue          = [];
  List<int>   _shuffleOrder   = [];
  int         _queueIndex     = 0;

  // Modes
  bool        _shuffle  = false;
  AppLoopMode _loop     = AppLoopMode.none;
  bool        _loading  = false;

  // Recently played
  RecentlyPlayedProvider? _recentlyPlayed;

  void attachRecentlyPlayed(RecentlyPlayedProvider rp) {
    _recentlyPlayed = rp;
  }

  // ── Getters ─────────────────────────────────────────────────────────────

  NowPlaying?  get current        => _current;
  Track?       get currentTrack   => _current?.local;
  bool         get loading        => _loading;
  bool         get playing        => _player.playing;
  Duration     get position       => _player.position;
  Duration     get duration       => _player.duration ?? Duration.zero;
  bool         get shuffle        => _shuffle;
  AppLoopMode  get loopMode       => _loop;
  int          get queueIndex     => _queueIndex;

  List<Track> get queue {
    if (_shuffle && _shuffleOrder.isNotEmpty) {
      return _shuffleOrder.map((i) => _queue[i]).toList();
    }
    return List.unmodifiable(_queue);
  }

  int get currentOrderedIndex => _queueIndex;

  Stream<Duration>    get positionStream    => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  bool get hasPrevious =>
      _current?.isStream == false &&
      (_queueIndex > 0 || _player.position.inSeconds > 3);

  bool get hasNext {
    if (_current?.isStream == true) return false;
    if (_loop == AppLoopMode.all)   return true;
    return _queueIndex < _queue.length - 1;
  }

  // ── Constructor ──────────────────────────────────────────────────────────

  PlayerProvider() {
    _player.playerStateStream.listen((_) => notifyListeners());
    _player.positionStream.listen((_) => notifyListeners());
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onTrackComplete();
    });
  }

  // ── Local playback ───────────────────────────────────────────────────────

  Future<void> playTrack(Track track) async {
    _queue      = [track];
    _queueIndex = 0;
    _rebuildShuffleOrder();
    await _loadLocalAt(0);
  }

  Future<void> playAll(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _queue      = List.from(tracks);
    _queueIndex = startIndex.clamp(0, tracks.length - 1);
    _rebuildShuffleOrder(startAt: startIndex);
    await _loadLocalAt(_queueIndex);
  }

  void playNext(Track track) {
    final insertAt = _queueIndex + 1;
    _queue.insert(insertAt, track);
    if (_shuffle) _shuffleOrder.insert(_queueIndex + 1, insertAt);
    notifyListeners();
  }

  void addToQueue(Track track) {
    _queue.add(track);
    if (_shuffle) _shuffleOrder.add(_queue.length - 1);
    notifyListeners();
  }

  Future<void> playQueueIndex(int orderedIndex) async {
    if (orderedIndex < 0 || orderedIndex >= _queue.length) return;
    _queueIndex = orderedIndex;
    await _loadLocalAt(_queueIndex);
  }

  Future<void> _loadLocalAt(int orderedIndex) async {
    final actualIndex = _shuffle && _shuffleOrder.isNotEmpty
        ? _shuffleOrder[orderedIndex]
        : orderedIndex;
    final track = _queue[actualIndex];
    _loading = true;
    _current = NowPlaying.local(track);
    notifyListeners();
    try {
      await _player.setFilePath(track.filePath);
      await _player.play();
      _logTrack(track); // ← log after successful playback starts
    } catch (_) {
      if (_queue.length > 1) await skipNext();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Online stream playback ───────────────────────────────────────────────

  Future<void> playStream(StreamTrack st) async {
    _queue   = [];
    _loading = true;
    _current = NowPlaying.stream(st);
    notifyListeners();
    try {
      await _player.setUrl(st.streamUrl);
      await _player.play();
      _logStream(st); // ← log after successful playback starts
    } catch (e) {
      debugPrint('Stream playback error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Controls ─────────────────────────────────────────────────────────────

  Future<void> togglePlayPause() async =>
      _player.playing ? await _player.pause() : await _player.play();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> skipNext() async {
    if (_current?.isStream == true) return;

    if (_loop == AppLoopMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    if (_queueIndex < _queue.length - 1) {
      _queueIndex++;
      await _loadLocalAt(_queueIndex);
    } else if (_loop == AppLoopMode.all && _queue.isNotEmpty) {
      _queueIndex = 0;
      if (_shuffle) _rebuildShuffleOrder();
      await _loadLocalAt(0);
    }
  }

  Future<void> skipPrevious() async {
    if (_current?.isStream == true) return;
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else if (_queueIndex > 0) {
      _queueIndex--;
      await _loadLocalAt(_queueIndex);
    }
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle) {
      _rebuildShuffleOrder(startAt: _queueIndex);
    }
    notifyListeners();
  }

  void toggleLoop() {
    _loop = AppLoopMode.values[(_loop.index + 1) % AppLoopMode.values.length];
    notifyListeners();
  }

  void _rebuildShuffleOrder({int startAt = 0}) {
    if (_queue.isEmpty) { _shuffleOrder = []; return; }
    final indices = List.generate(_queue.length, (i) => i)
      ..remove(startAt)
      ..shuffle(_rng);
    _shuffleOrder = [startAt, ...indices];
    _queueIndex   = 0;
  }

  void _onTrackComplete() {
    if (_loop == AppLoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
    } else if (hasNext) {
      skipNext();
    }
  }

  // ── Recently played helpers ───────────────────────────────────────────────

  void _logTrack(Track track) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _recentlyPlayed?.logTrack(track);
    });
  }

  void _logStream(StreamTrack st) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _recentlyPlayed?.logStream(StreamTrackInfo(
        youtubeUrl:   st.youtubeUrl,
        title:        st.title,
        artist:       st.artist,
        thumbnailUrl: st.thumbnailUrl,
      ));
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

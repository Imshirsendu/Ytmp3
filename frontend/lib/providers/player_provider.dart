import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/search_result.dart';
import '../models/track.dart';
import 'recently_played_provider.dart';

// ── LastSession ───────────────────────────────────────────────────────────────

class LastSession {
  final String filePath;
  final String title;
  final String artist;
  final Duration position;

  const LastSession({
    required this.filePath,
    required this.title,
    required this.artist,
    required this.position,
  });
}

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

// ── Equalizer presets ────────────────────────────────────────────────────────

enum EqPreset { flat, bassBoost, vocal }

extension EqPresetLabel on EqPreset {
  String get label => switch (this) {
        EqPreset.flat      => 'Flat',
        EqPreset.bassBoost => 'Bass Boost',
        EqPreset.vocal     => 'Vocal',
      };

  String get emoji => switch (this) {
        EqPreset.flat      => '〰️',
        EqPreset.bassBoost => '🔊',
        EqPreset.vocal     => '🎤',
      };
}

/// dB gains per preset for a 5-band EQ: 60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz
const _presetGains = {
  EqPreset.flat:      [0.0,  0.0,  0.0,  0.0,  0.0],
  EqPreset.bassBoost: [8.0,  5.0,  0.0, -2.0, -3.0],
  EqPreset.vocal:     [-2.0, 0.0,  5.0,  6.0,  3.0],
};

// ── PlayerProvider ───────────────────────────────────────────────────────────

class PlayerProvider extends ChangeNotifier {
  final _rng = Random();

  // Equalizer chain — Android only
  AndroidEqualizer?       _equalizer;
  AndroidLoudnessEnhancer? _loudness;
  late final AudioPlayer  _player;

  EqPreset _eqPreset = EqPreset.flat;
  bool     _eqReady  = false;

  NowPlaying? _current;

  List<Track> _queue        = [];
  List<int>   _shuffleOrder = [];
  int         _queueIndex   = 0;

  bool        _shuffle = false;
  AppLoopMode _loop    = AppLoopMode.none;
  bool        _loading = false;

  RecentlyPlayedProvider? _recentlyPlayed;

  // ── Sleep timer ───────────────────────────────────────────────────────────
  Timer?    _sleepTimer;
  DateTime? _sleepEndsAt;

  // ── Session persistence ───────────────────────────────────────────────────
  static const _kFilePath  = 'session_file_path';
  static const _kTitle     = 'session_title';
  static const _kArtist    = 'session_artist';
  static const _kPositionMs = 'session_position_ms';
  Timer?    _sessionSaveTimer;

  void attachRecentlyPlayed(RecentlyPlayedProvider rp) {
    _recentlyPlayed = rp;
  }

  // ── Getters ──────────────────────────────────────────────────────────────

  NowPlaying?  get current   => _current;
  Track?       get currentTrack => _current?.local;
  bool         get loading   => _loading;
  bool         get playing   => _player.playing;
  Duration     get position  => _player.position;
  Duration     get duration  => _player.duration ?? Duration.zero;
  bool         get shuffle   => _shuffle;
  AppLoopMode  get loopMode  => _loop;
  int          get queueIndex => _queueIndex;
  EqPreset     get eqPreset  => _eqPreset;
  bool         get eqReady   => _eqReady;

  // Sleep timer getters
  bool      get sleepTimerActive => _sleepTimer?.isActive ?? false;
  Duration? get sleepRemaining {
    if (_sleepEndsAt == null || !sleepTimerActive) return null;
    final rem = _sleepEndsAt!.difference(DateTime.now());
    return rem.isNegative ? Duration.zero : rem;
  }

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

  // ── Constructor ───────────────────────────────────────────────────────────

  PlayerProvider() {
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _equalizer = AndroidEqualizer();
      _loudness  = AndroidLoudnessEnhancer();
      _player = AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: [_loudness!, _equalizer!],
        ),
      );
      _eqReady = true;
    } catch (_) {
      // Non-Android or unsupported — fall back to plain player
      _equalizer = null;
      _loudness  = null;
      _player    = AudioPlayer();
    }

    _player.playerStateStream.listen((_) => notifyListeners());
    _player.positionStream.listen((_) {
      notifyListeners();
      _throttledSaveSession();
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onTrackComplete();
    });

    notifyListeners();
  }

  // ── Equalizer API ─────────────────────────────────────────────────────────

  Future<void> setEqPreset(EqPreset preset) async {
    _eqPreset = preset;
    notifyListeners();
    if (_equalizer == null) return;
    try {
      final params = await _equalizer!.parameters;
      final bands  = params.bands;
      final gains  = _presetGains[preset]!;
      for (var i = 0; i < bands.length && i < gains.length; i++) {
        await bands[i].setGain(gains[i]);
      }
    } catch (e) {
      debugPrint('EQ setPreset error: $e');
    }
  }

  // ── Local playback ────────────────────────────────────────────────────────

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
      _logTrack(track);
    } catch (_) {
      if (_queue.length > 1) await skipNext();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Online stream playback ────────────────────────────────────────────────

  Future<void> playStream(StreamTrack st) async {
    _queue   = [];
    _loading = true;
    _current = NowPlaying.stream(st);
    notifyListeners();
    try {
      await _player.setUrl(st.streamUrl);
      await _player.play();
      _logStream(st);
    } catch (e) {
      debugPrint('Stream playback error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Controls ──────────────────────────────────────────────────────────────

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
    if (_shuffle) _rebuildShuffleOrder(startAt: _queueIndex);
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

  // ── Sleep timer ───────────────────────────────────────────────────────────

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepEndsAt = DateTime.now().add(duration);
    _sleepTimer  = Timer(duration, () async {
      await _player.pause();
      _sleepEndsAt = null;
      notifyListeners();
    });
    // Tick every 30s so the countdown in the UI stays fresh
    Timer.periodic(const Duration(seconds: 30), (t) {
      if (!sleepTimerActive) { t.cancel(); return; }
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer  = null;
    _sleepEndsAt = null;
    notifyListeners();
  }

  // ── Session persistence ───────────────────────────────────────────────────

  /// Throttled — writes at most once every 5 seconds while playing.
  void _throttledSaveSession() {
    if (_current == null || _current!.isStream) return;
    if (_sessionSaveTimer?.isActive ?? false) return;
    _sessionSaveTimer = Timer(const Duration(seconds: 5), _saveSession);
  }

  Future<void> _saveSession() async {
    final track = _current?.local;
    if (track == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFilePath,   track.filePath);
      await prefs.setString(_kTitle,      track.title);
      await prefs.setString(_kArtist,     track.artist);
      await prefs.setInt(_kPositionMs, _player.position.inMilliseconds);
    } catch (e) {
      debugPrint('Session save error: $e');
    }
  }

  /// Call once on app start (e.g. in initState of your home screen).
  /// Returns a [LastSession] if one exists, null otherwise.
  static Future<LastSession?> loadLastSession() async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final filePath = prefs.getString(_kFilePath);
      final title    = prefs.getString(_kTitle);
      final artist   = prefs.getString(_kArtist);
      final posMs    = prefs.getInt(_kPositionMs);
      if (filePath == null || title == null || artist == null) return null;
      return LastSession(
        filePath: filePath,
        title:    title,
        artist:   artist,
        position: Duration(milliseconds: posMs ?? 0),
      );
    } catch (_) {
      return null;
    }
  }

  /// Clear the saved session (call after user dismisses resume banner).
  static Future<void> clearLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFilePath);
    await prefs.remove(_kTitle);
    await prefs.remove(_kArtist);
    await prefs.remove(_kPositionMs);
  }

  /// Resume the last session — loads the track and seeks to saved position.
  Future<void> resumeSession(LastSession session, Track track) async {
    await playTrack(track);
    await _player.seek(session.position);
    await clearLastSession();
  }

  // ── Recently played ───────────────────────────────────────────────────────

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
    _sleepTimer?.cancel();
    _sessionSaveTimer?.cancel();
    _saveSession(); // flush final position synchronously-ish
    _equalizer?.release();
    _loudness?.release();
    _player.dispose();
    super.dispose();
  }
}

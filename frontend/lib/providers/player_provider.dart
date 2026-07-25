import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';

/// A lightweight track-like object for online streams that haven't been
/// downloaded — no filePath, just a remote URL and metadata.
class StreamTrack {
  final String youtubeUrl;  // original YT URL (used as ID)
  final String streamUrl;   // direct CDN URL returned by /stream
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

/// Represents what is currently loaded — either a local Track or an online
/// StreamTrack. Exactly one field is non-null.
class NowPlaying {
  final Track? local;
  final StreamTrack? stream;

  const NowPlaying.local(this.local) : stream = null;
  const NowPlaying.stream(this.stream) : local = null;

  String get title  => local?.title  ?? stream?.title  ?? '';
  String get artist => local?.artist ?? stream?.artist ?? '';
  bool get isStream => stream != null;
}

class PlayerProvider extends ChangeNotifier {
  final _player = AudioPlayer();

  NowPlaying? _current;
  List<Track> _queue = [];      // local track queue
  int _queueIndex = 0;
  bool _loading = false;

  NowPlaying? get current => _current;
  Track?      get currentTrack  => _current?.local;
  bool        get loading       => _loading;
  bool        get playing       => _player.playing;
  Duration    get position      => _player.position;
  Duration    get duration      => _player.duration ?? Duration.zero;
  List<Track> get queue         => List.unmodifiable(_queue);
  int         get queueIndex    => _queueIndex;

  Stream<Duration>    get positionStream    => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  PlayerProvider() {
    _player.playerStateStream.listen((_) => notifyListeners());
    _player.positionStream.listen((_) => notifyListeners());
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onTrackComplete();
    });
  }

  // ── Local playback ────────────────────────────────────────────────────────

  Future<void> playTrack(Track track) async {
    _queue = [track];
    _queueIndex = 0;
    await _loadLocal(track);
  }

  Future<void> playAll(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _queue = List.from(tracks);
    _queueIndex = startIndex.clamp(0, tracks.length - 1);
    await _loadLocal(_queue[_queueIndex]);
  }

  Future<void> _loadLocal(Track track) async {
    _loading = true;
    _current = NowPlaying.local(track);
    notifyListeners();
    try {
      await _player.setFilePath(track.filePath);
      await _player.play();
    } catch (_) {
      if (_queue.length > 1) await skipNext();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Online stream playback ────────────────────────────────────────────────

  Future<void> playStream(StreamTrack st) async {
    _queue = [];        // clear local queue when streaming
    _loading = true;
    _current = NowPlaying.stream(st);
    notifyListeners();
    try {
      await _player.setUrl(st.streamUrl);
      await _player.play();
    } catch (e) {
      debugPrint('Stream playback error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> togglePlayPause() async {
    _player.playing ? await _player.pause() : await _player.play();
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> skipNext() async {
    if (_queueIndex < _queue.length - 1) {
      _queueIndex++;
      await _loadLocal(_queue[_queueIndex]);
    }
  }

  Future<void> skipPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else if (_queueIndex > 0) {
      _queueIndex--;
      await _loadLocal(_queue[_queueIndex]);
    }
  }

  Future<void> playQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queueIndex = index;
    await _loadLocal(_queue[_queueIndex]);
  }

  bool get hasPrevious =>
      (_current?.isStream == false) &&
      (_queueIndex > 0 || _player.position.inSeconds > 3);

  bool get hasNext =>
      (_current?.isStream == false) && _queueIndex < _queue.length - 1;

  void _onTrackComplete() {
    if (hasNext) skipNext();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

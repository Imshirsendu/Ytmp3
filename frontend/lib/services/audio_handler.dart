import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Bridges just_audio ↔ audio_service so the OS can control playback via
/// lock-screen controls, Bluetooth headsets, and notification media buttons.
class YtMp3AudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();

  YtMp3AudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.currentIndexStream.listen((index) {
      if (index != null && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
    });
  }

  // ── Queue management ──────────────────────────────────────────────────────

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    queue.add([...queue.value, ...mediaItems]);
    await _updatePlayerSource();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    final newQueue = List<MediaItem>.from(queue.value)..removeAt(index);
    queue.add(newQueue);
    await _updatePlayerSource();
  }

  Future<void> setQueueAndPlay(List<MediaItem> items, int index) async {
    queue.add(items);
    await _updatePlayerSource();
    await _player.seek(Duration.zero, index: index);
    await play();
  }

  Future<void> _updatePlayerSource() async {
    final sources = queue.value
        .map((item) => AudioSource.uri(Uri.parse(item.id)))
        .toList();
    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: _player.currentIndex ?? 0,
      preload: false,
    );
  }

  // ── Playback controls ─────────────────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    await _player.setShuffleModeEnabled(
        mode == AudioServiceShuffleMode.all);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode mode) async {
    final loopMode = switch (mode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one  => LoopMode.one,
      _                           => LoopMode.all,
    };
    await _player.setLoopMode(loopMode);
  }

  // ── Public player access (for UI slider, volume, etc.) ───────────────────

  AudioPlayer get player => _player;

  // ── State broadcasting ────────────────────────────────────────────────────

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: switch (_player.processingState) {
        ProcessingState.idle        => AudioProcessingState.idle,
        ProcessingState.loading     => AudioProcessingState.loading,
        ProcessingState.buffering   => AudioProcessingState.buffering,
        ProcessingState.ready       => AudioProcessingState.ready,
        ProcessingState.completed   => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }

  @override
  Future<void> onTaskRemoved() async {
    await _player.dispose();
    await super.onTaskRemoved();
  }
}

import 'dart:typed_data';

/// Represents a single downloaded MP3 track stored on-device.
class Track {
  final String id;        // Absolute file path (unique key)
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String filePath;
  final DateTime dateAdded;
  final Uint8List? coverArt; // Raw JPEG bytes from ID3 APIC tag

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.filePath,
    required this.dateAdded,
    this.coverArt,
  });

  @override
  bool operator ==(Object other) =>
      other is Track && other.filePath == filePath;

  @override
  int get hashCode => filePath.hashCode;
}

/// Download job tracked in the UI queue.
enum DownloadStatus { queued, downloading, converting, done, error }

class DownloadJob {
  final String id;
  final String url;
  String title;
  DownloadStatus status;
  double progress; // 0.0 – 1.0
  String speed;    // e.g. "1.2 MB/s"
  String? errorMessage;

  DownloadJob({
    required this.id,
    required this.url,
    this.title = 'Fetching info…',
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.speed = '',
    this.errorMessage,
  });
}

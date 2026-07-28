import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:media_scanner/media_scanner.dart';

import '../models/track.dart';

class DownloadProvider extends ChangeNotifier {
  final _jobs = <String, DownloadJob>{};
  final _dio = Dio();
  final _uuid = const Uuid();

  List<DownloadJob> get jobs =>
      _jobs.values.toList().reversed.toList();

  /// [title] should be the video title from search results so the saved
  /// filename is human-readable. Falls back to a UUID if not provided.
  Future<void> enqueue(
    String url,
    String serverDownloadUrl, {
    String? title,
  }) async {
    if (url.trim().isEmpty || serverDownloadUrl.trim().isEmpty) {
      debugPrint('DownloadProvider: invalid URL — url=$url dl=$serverDownloadUrl');
      return;
    }
    final job = DownloadJob(
      id: _uuid.v4(),
      url: url,
      title: title ?? 'Downloading…',
    );
    _jobs[job.id] = job;
    notifyListeners();
    debugPrint('DownloadProvider: starting download → $serverDownloadUrl');
    await _runJob(job, serverDownloadUrl, title: title);
  }

  Future<void> _runJob(
    DownloadJob job,
    String serverDownloadUrl, {
    String? title,
  }) async {
    final dir = await _musicDir();
    if (dir == null) {
      job.status = DownloadStatus.error;
      job.errorMessage = 'Storage permission denied';
      notifyListeners();
      return;
    }

    // Use the video title as filename (sanitised), fallback to job id
    final safeName = _safeFilename(title ?? job.id);
    final finalPath = '${dir.path}/$safeName.mp3';

    job.status = DownloadStatus.downloading;
    notifyListeners();

    try {
      await _dio.download(
        serverDownloadUrl,
        finalPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            job.progress = received / total;
            job.speed = '${(received / 1024 / 1024).toStringAsFixed(1)} MB';
            notifyListeners();
          }
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          // ResponseType must NOT be bytes for dio.download() — it handles streaming internally
        ),
      );

      job.title = title ?? safeName;
      job.status = DownloadStatus.done;
      job.progress = 1.0;

      // Tell Android MediaStore about the new file so it appears in file
      // managers and music apps immediately without needing a device reboot.
      if (Platform.isAndroid) {
        try {
          await MediaScanner.loadMedia(path: finalPath);
        } catch (e) {
          debugPrint('MediaScanner error (non-fatal): $e');
        }
      }
    } on DioException catch (e) {
      await File(finalPath).delete().catchError((_) => File(finalPath));
      job.status = DownloadStatus.error;
      job.errorMessage = _friendlyError(e);
    } catch (e) {
      job.status = DownloadStatus.error;
      job.errorMessage = e.toString();
    }

    notifyListeners();
  }

  /// Resolves to /sdcard/Music/YT-MP3 on Android (visible in file manager).
  /// Falls back to app-private documents on iOS or if permission is denied.
  Future<Directory?> _musicDir() async {
    if (Platform.isAndroid) {
      // Android 13+ (API 33+): Permission.storage is deprecated, use Permission.audio.
      // Android 10-12: needs Permission.storage.
      // Request both — whichever applies will be granted by the OS.
      final results = await [Permission.storage, Permission.audio].request();
      final granted = (results[Permission.storage]?.isGranted ?? false) ||
                      (results[Permission.audio]?.isGranted ?? false);
      if (!granted) return _fallbackDir();

      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final parts = ext.path.split('/');
          final androidIdx = parts.indexOf('Android');
          final sdcard = androidIdx > 0
              ? parts.sublist(0, androidIdx).join('/')
              : ext.path;
          final dir = Directory('$sdcard/Music/YT-MP3');
          if (!dir.existsSync()) dir.createSync(recursive: true);
          return dir;
        }
      } catch (_) {}
    }

    return _fallbackDir();
  }

  Future<Directory> _fallbackDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Music');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Strips characters that are illegal in Android filenames.
  String _safeFilename(String raw) {
    final sanitized = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized.substring(0, sanitized.length.clamp(0, 100));
  }

  String _friendlyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout) return 'Server unreachable';
    if (e.type == DioExceptionType.receiveTimeout) return 'Download timed out';
    if (e.response?.statusCode == 404) return 'Video not found or private';
    if (e.response?.statusCode == 422) return 'Invalid URL';
    return e.message ?? 'Unknown error';
  }

  void removeJob(String id) {
    _jobs.remove(id);
    notifyListeners();
  }

  void clearCompleted() {
    _jobs.removeWhere((_, j) =>
        j.status == DownloadStatus.done || j.status == DownloadStatus.error);
    notifyListeners();
  }
}

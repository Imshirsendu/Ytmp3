import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ServerStatus { unknown, checking, online, offline }

class ServerProvider extends ChangeNotifier {
  static const _prefKey    = 'server_url';
  static const _defaultUrl = 'http://192.168.1.100:8000';

  String _serverUrl = _defaultUrl;
  ServerStatus _status = ServerStatus.unknown;
  Timer? _pingTimer;

  String get serverUrl => _serverUrl;
  ServerStatus get status => _status;
  bool get isOnline => _status == ServerStatus.online;

  ServerProvider() {
    _loadUrl().then((_) => _startPing());
  }

  Future<void> _loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_prefKey) ?? _defaultUrl;
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    _serverUrl = url.trimRight().replaceAll(RegExp(r'/$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _serverUrl);
    notifyListeners();
    await checkNow();
  }

  void _startPing() {
    checkNow();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => checkNow());
  }

  Future<void> checkNow() async {
    _status = ServerStatus.checking;
    notifyListeners();
    try {
      final res = await Dio().get(
        '$_serverUrl/health',
        options: Options(
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      _status = (res.statusCode == 200) ? ServerStatus.online : ServerStatus.offline;
    } catch (_) {
      _status = ServerStatus.offline;
    }
    notifyListeners();
  }

  /// Download URL — returns a 320kbps MP3 file.
  String downloadUrl(String youtubeUrl) =>
      '$_serverUrl/download?url=${Uri.encodeQueryComponent(youtubeUrl)}';

  /// Stream info URL — returns JSON with title, artist, thumbnail, duration.
  /// Use this to get metadata before setting up the proxy stream.
  String streamInfoUrl(String youtubeUrl) =>
      '$_serverUrl/stream/info?url=${Uri.encodeQueryComponent(youtubeUrl)}';

  /// Stream proxy URL — point just_audio at this.
  /// The server fetches YouTube CDN audio with correct headers and pipes it back.
  String streamProxyUrl(String youtubeUrl) =>
      '$_serverUrl/stream?url=${Uri.encodeQueryComponent(youtubeUrl)}';

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }
}

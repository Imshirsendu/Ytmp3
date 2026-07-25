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
    _pingTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => checkNow());
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
      _status =
          (res.statusCode == 200) ? ServerStatus.online : ServerStatus.offline;
    } catch (_) {
      _status = ServerStatus.offline;
    }

    notifyListeners();
  }

  /// URL to download a YouTube video as a 320 kbps MP3.
  String downloadUrl(String youtubeUrl) =>
      '$_serverUrl/download?url=${Uri.encodeQueryComponent(youtubeUrl)}';

  /// URL to fetch a direct audio stream URL (returns JSON with stream_url).
  String streamInfoUrl(String youtubeUrl) =>
      '$_serverUrl/stream?url=${Uri.encodeQueryComponent(youtubeUrl)}';

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }
}

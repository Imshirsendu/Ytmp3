import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AudioBitrate {
  kbps128,
  kbps192,
  kbps256,
  kbps320,
}

extension AudioBitrateExt on AudioBitrate {
  String get label => switch (this) {
        AudioBitrate.kbps128 => '128 kbps',
        AudioBitrate.kbps192 => '192 kbps',
        AudioBitrate.kbps256 => '256 kbps',
        AudioBitrate.kbps320 => '320 kbps',
      };

  String get description => switch (this) {
        AudioBitrate.kbps128 => 'Smaller files, lower quality',
        AudioBitrate.kbps192 => 'Good balance',
        AudioBitrate.kbps256 => 'High quality',
        AudioBitrate.kbps320 => 'Best quality, larger files',
      };

  /// The value sent as the `bitrate` query param to the backend.
  int get value => switch (this) {
        AudioBitrate.kbps128 => 128,
        AudioBitrate.kbps192 => 192,
        AudioBitrate.kbps256 => 256,
        AudioBitrate.kbps320 => 320,
      };
}

class SettingsProvider extends ChangeNotifier {
  static const _kBitrate = 'download_bitrate';

  AudioBitrate _bitrate = AudioBitrate.kbps192;

  AudioBitrate get bitrate => _bitrate;

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_kBitrate);
      if (stored != null) {
        _bitrate = AudioBitrate.values.firstWhere(
          (b) => b.value == stored,
          orElse: () => AudioBitrate.kbps192,
        );
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setBitrate(AudioBitrate bitrate) async {
    _bitrate = bitrate;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kBitrate, bitrate.value);
    } catch (_) {}
  }
}

import 'package:shared_preferences/shared_preferences.dart';

class SavedPcConnection {
  const SavedPcConnection({
    required this.serverUrl,
    required this.deviceName,
    required this.lastPath,
  });

  final String serverUrl;
  final String deviceName;
  final String lastPath;

  bool get exists => serverUrl.trim().isNotEmpty;
}

class ConnectionStore {
  static const _serverUrlKey = 'pyclean.server_url';
  static const _deviceNameKey = 'pyclean.device_name';
  static const _lastPathKey = 'pyclean.last_path';

  Future<SavedPcConnection> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      return SavedPcConnection(
        serverUrl: prefs.getString(_serverUrlKey) ?? '',
        deviceName: prefs.getString(_deviceNameKey) ?? 'PyClean PC',
        lastPath: prefs.getString(_lastPathKey) ?? '',
      );
    } catch (_) {
      // Keeps widget/unit tests and unsupported platforms usable even when
      // SharedPreferences is unavailable.
      return const SavedPcConnection(
        serverUrl: '',
        deviceName: 'PyClean PC',
        lastPath: '',
      );
    }
  }

  Future<void> saveConnection({
    required String serverUrl,
    required String deviceName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, serverUrl);
    await prefs.setString(_deviceNameKey, deviceName);
  }

  Future<void> saveLastPath(String path) async {
    if (path.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPathKey, path);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverUrlKey);
    await prefs.remove(_deviceNameKey);
    await prefs.remove(_lastPathKey);
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;


class ServerStatusResult {
  const ServerStatusResult({
    required this.statusCode,
    required this.status,
    required this.deviceName,
    required this.ip,
    required this.port,
    required this.running,
    required this.rawBody,
  });

  final int statusCode;
  final String status;
  final String deviceName;
  final String ip;
  final int port;
  final bool running;
  final String rawBody;

  bool get isSuccess => statusCode == 200 && running;
}

class BrowseResult {
  const BrowseResult({
    required this.statusCode,
    required this.currentPath,
    required this.parentPath,
    required this.items,
    required this.rawBody,
  });

  final int statusCode;
  final String currentPath;
  final String parentPath;
  final List<dynamic> items;
  final String rawBody;

  bool get isSuccess => statusCode == 200;
}

class ApiActionResult {
  const ApiActionResult({
    required this.statusCode,
    required this.rawBody,
    this.message,
  });

  final int statusCode;
  final String rawBody;
  final String? message;

  bool get isSuccess => statusCode == 200;
}

class PyCleanApi {
  String _serverUrl = '';

  String get serverUrl => _serverUrl;
  bool get isConfigured => _serverUrl.isNotEmpty;

  void setServerUrl(String url) {
    var normalized = url.trim();

    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    _serverUrl = normalized;
  }

  Future<ServerStatusResult> status({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    _requireServer();

    final response = await http
        .get(Uri.parse('$_serverUrl/api/status'))
        .timeout(timeout);

    final data = _decodeObject(response.body);

    return ServerStatusResult(
      statusCode: response.statusCode,
      status: data['status']?.toString() ?? '',
      deviceName: data['device_name']?.toString() ?? 'PyClean PC',
      ip: data['ip']?.toString() ?? '',
      port: int.tryParse(data['port']?.toString() ?? '') ?? 0,
      running: data['running'] == true || data['status'] == 'online',
      rawBody: response.body,
    );
  }

  Future<BrowseResult> browse(String? path) async {
    _requireServer();

    final response = await http.post(
      Uri.parse('$_serverUrl/api/browse'),
      headers: const {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'path': path,
      }),
    );

    if (response.statusCode != 200) {
      return BrowseResult(
        statusCode: response.statusCode,
        currentPath: '',
        parentPath: '',
        items: const [],
        rawBody: response.body,
      );
    }

    final data = _decodeObject(response.body);
    final rawItems = data['items'];

    return BrowseResult(
      statusCode: response.statusCode,
      currentPath: data['current_path']?.toString() ?? '',
      parentPath: data['parent_path']?.toString() ?? '',
      items: rawItems is List ? List<dynamic>.from(rawItems) : const [],
      rawBody: response.body,
    );
  }

  Future<ApiActionResult> uploadFile({
    required String targetDirectory,
    required String filePath,
  }) async {
    _requireServer();

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_serverUrl/api/upload'),
    );

    request.fields['target_dir'] = targetDirectory;
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    return ApiActionResult(
      statusCode: response.statusCode,
      rawBody: response.body,
      message: _tryReadMessage(response.body),
    );
  }

  Future<ApiActionResult> sortFolder(String targetPath) async {
    return _postJsonAction(
      '/api/execute-sort',
      {
        'target_dir': targetPath,
      },
    );
  }

  Future<ApiActionResult> deleteItem(String itemPath) async {
    return _postJsonAction(
      '/api/delete',
      {
        'path': itemPath,
      },
    );
  }

  Future<ApiActionResult> _postJsonAction(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    _requireServer();

    final response = await http.post(
      Uri.parse('$_serverUrl$endpoint'),
      headers: const {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    // The existing C++ API returns JSON for these action endpoints.
    // Decode here so malformed responses still surface as errors just as
    // they did when jsonDecode lived in the screen.
    final data = _decodeObject(response.body);

    return ApiActionResult(
      statusCode: response.statusCode,
      rawBody: response.body,
      message: data['message']?.toString(),
    );
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object from PyClean server');
    }

    return decoded;
  }

  String? _tryReadMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded['message']?.toString();
      }
    } catch (_) {
      // Upload previously exposed the raw response body on failure, so a
      // non-JSON response is valid information for the UI to display.
    }

    return null;
  }

  void _requireServer() {
    if (!isConfigured) {
      throw StateError('PyClean server URL is not configured');
    }
  }
}

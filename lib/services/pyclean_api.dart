import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    required this.shareEnabled,
    required this.sharedRoot,
    required this.sharedName,
    required this.readOnly,
    required this.canBrowse,
    required this.canDownload,
    required this.canUpload,
    required this.canRename,
    required this.canMove,
    required this.canDelete,
    required this.canSort,
  });

  final int statusCode;
  final String status;
  final String deviceName;
  final String ip;
  final int port;
  final bool running;
  final String rawBody;

  final bool shareEnabled;
  final String sharedRoot;
  final String sharedName;
  final bool readOnly;

  final bool canBrowse;
  final bool canDownload;
  final bool canUpload;
  final bool canRename;
  final bool canMove;
  final bool canDelete;
  final bool canSort;

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
    this.savedPath,
    this.filename,
  });

  final int statusCode;
  final String rawBody;
  final String? message;
  final String? savedPath;
  final String? filename;

  bool get isSuccess => statusCode == 200;
}

class DownloadResult {
  const DownloadResult({
    required this.statusCode,
    required this.bytes,
    required this.rawBody,
    this.message,
  });

  final int statusCode;
  final Uint8List bytes;
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

    if (normalized.isNotEmpty &&
        !normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    _serverUrl = normalized;
  }

  Future<ServerStatusResult> status({
    Duration timeout = const Duration(seconds: 8),
    int attempts = 1,
  }) async {
    _requireServer();

    final uri = Uri.tryParse('$_serverUrl/api/status');
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw FormatException('Invalid PyClean server URL: $_serverUrl');
    }

    final safeAttempts = attempts < 1 ? 1 : attempts;

    for (var attempt = 1; attempt <= safeAttempts; attempt++) {
      try {
        final response = await http
            .get(
              uri,
              headers: const {'Connection': 'close'},
            )
            .timeout(timeout);

        final data = _decodeObject(response.body);
        final rawPermissions = data['permissions'];
        final permissions = rawPermissions is Map
            ? Map<String, dynamic>.from(rawPermissions)
            : const <String, dynamic>{};

        bool permission(String key) => permissions[key] != false;

        return ServerStatusResult(
          statusCode: response.statusCode,
          status: data['status']?.toString() ?? '',
          deviceName: data['device_name']?.toString() ?? 'PyClean PC',
          ip: data['ip']?.toString() ?? '',
          port: int.tryParse(data['port']?.toString() ?? '') ?? 0,
          running: data['running'] == true || data['status'] == 'online',
          rawBody: response.body,
          shareEnabled: data['share_enabled'] == true,
          sharedRoot: data['shared_root']?.toString() ?? '',
          sharedName: data['shared_name']?.toString() ?? '',
          readOnly: data['read_only'] == true,
          canBrowse: permission('browse'),
          canDownload: permission('download'),
          canUpload: permission('upload'),
          canRename: permission('rename'),
          canMove: permission('move'),
          canDelete: permission('delete'),
          canSort: permission('sort'),
        );
      } catch (_) {
        if (attempt >= safeAttempts) {
          rethrow;
        }

        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }

    throw StateError('PyClean status probe failed unexpectedly');
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
    TransferProgressCallback? onProgress,
    PyCleanTransferController? controller,
  }) async {
    _requireServer();

    final request = _ProgressMultipartRequest(
      'POST',
      Uri.parse('$_serverUrl/api/upload'),
      onProgress: onProgress,
    );

    request.fields['target_dir'] = targetDirectory;
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
      ),
    );

    final client = http.Client();
    controller?._attach(client);

    try {
      if (controller?.isCancelled == true) {
        throw const PyCleanTransferCancelled();
      }

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (controller?.isCancelled == true) {
        throw const PyCleanTransferCancelled();
      }

      final data = _tryDecodeObject(response.body);

      return ApiActionResult(
        statusCode: response.statusCode,
        rawBody: response.body,
        message: data?['message']?.toString() ?? _tryReadMessage(response.body),
        savedPath: data?['path']?.toString(),
        filename: data?['filename']?.toString(),
      );
    } on http.ClientException {
      if (controller?.isCancelled == true) {
        throw const PyCleanTransferCancelled();
      }
      rethrow;
    } finally {
      controller?._detach(client);
      client.close();
    }
  }

  Future<DownloadResult> downloadFile(
    String filePath, {
    TransferProgressCallback? onProgress,
    PyCleanTransferController? controller,
  }) async {
    _requireServer();

    final request = http.Request(
      'POST',
      Uri.parse('$_serverUrl/api/download'),
    )
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'path': filePath,
      });

    final client = http.Client();
    controller?._attach(client);

    try {
      if (controller?.isCancelled == true) {
        throw const PyCleanTransferCancelled();
      }

      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        final response = await http.Response.fromStream(streamedResponse);

        return DownloadResult(
          statusCode: response.statusCode,
          bytes: Uint8List(0),
          rawBody: response.body,
          message: _tryReadMessage(response.body),
        );
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      final buffer = BytesBuilder(copy: false);
      var receivedBytes = 0;

      await for (final chunk in streamedResponse.stream) {
        if (controller?.isCancelled == true) {
          throw const PyCleanTransferCancelled();
        }

        buffer.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes);
      }

      if (controller?.isCancelled == true) {
        throw const PyCleanTransferCancelled();
      }

      return DownloadResult(
        statusCode: streamedResponse.statusCode,
        bytes: buffer.takeBytes(),
        rawBody: '',
      );
    } on http.ClientException {
      if (controller?.isCancelled == true) {
        throw const PyCleanTransferCancelled();
      }
      rethrow;
    } finally {
      controller?._detach(client);
      client.close();
    }
  }

  Future<ApiActionResult> renameItem({
    required String itemPath,
    required String newName,
  }) async {
    return _postJsonAction(
      '/api/rename',
      {
        'path': itemPath,
        'new_name': newName,
      },
    );
  }

  Future<ApiActionResult> moveItem({
    required String itemPath,
    required String targetDirectory,
  }) async {
    return _postJsonAction(
      '/api/move',
      {
        'path': itemPath,
        'target_dir': targetDirectory,
      },
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

  Map<String, dynamic>? _tryDecodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Keep the raw response available to callers when a server returns text.
    }

    return null;
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


typedef TransferProgressCallback = void Function(
  int transferredBytes,
  int totalBytes,
);

class PyCleanTransferCancelled implements Exception {
  const PyCleanTransferCancelled();

  @override
  String toString() => 'PyClean transfer cancelled';
}

class PyCleanTransferController {
  http.Client? _client;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  void _attach(http.Client client) {
    _client = client;
    if (_cancelled) {
      client.close();
    }
  }

  void _detach(http.Client client) {
    if (identical(_client, client)) {
      _client = null;
    }
  }
}

class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(
    super.method,
    super.url, {
    this.onProgress,
  });

  final TransferProgressCallback? onProgress;

  @override
  http.ByteStream finalize() {
    final totalBytes = contentLength;
    final source = super.finalize();

    if (onProgress == null) {
      return source;
    }

    var sentBytes = 0;
    final stream = source.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          sentBytes += chunk.length;
          onProgress?.call(sentBytes, totalBytes);
          sink.add(chunk);
        },
      ),
    );

    return http.ByteStream(stream);
  }
}

String pyCleanTransferMessage(Object error) {
  if (error is PyCleanTransferCancelled) {
    return 'Transfer cancelled.';
  }

  if (error is TimeoutException ||
      error is SocketException ||
      error is http.ClientException) {
    return pyCleanConnectionMessage(error);
  }

  return 'Transfer failed. Check the file and network connection.';
}

String pyCleanConnectionMessage(Object error) {
  if (error is TimeoutException) {
    return 'The PC did not respond. Check that PyClean Agent is running and both devices are on the same local network.';
  }

  if (error is SocketException || error is http.ClientException) {
    return 'The PC is unreachable. Check the local network and saved PC address.';
  }

  if (error is FormatException) {
    return 'Invalid PyClean address or response. Scan a fresh QR code.';
  }

  if (error is StateError) {
    return 'PyClean Agent is not ready or is offline.';
  }

  return 'Could not connect to the PyClean PC. Check the network and try again.';
}

String pyCleanTechnicalDetails(Object error) => error.toString();


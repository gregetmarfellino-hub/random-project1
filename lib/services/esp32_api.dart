import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/esp32_device.dart';

class Esp32Api {
  Esp32Api({
    this.baseUrl = 'http://pyclean-esp32.local',
  });

  final String baseUrl;

  Future<Esp32Device> status({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final response = await http
        .get(Uri.parse('$normalized/status'))
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw StateError(
        'ESP32 returned HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ESP32 /status did not return a JSON object');
    }

    return Esp32Device.fromJson(decoded);
  }
}

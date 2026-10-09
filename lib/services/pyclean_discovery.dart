import 'package:flutter/services.dart';

class DiscoveredPyCleanDevice {
  const DiscoveredPyCleanDevice({
    required this.serviceName,
    required this.serviceType,
    required this.host,
    required this.port,
  });

  final String serviceName;
  final String serviceType;
  final String host;
  final int port;

  String get baseUrl {
    final normalizedHost = host.contains(':') ? '[$host]' : host;
    return 'http://$normalizedHost:$port';
  }

  factory DiscoveredPyCleanDevice.fromMap(Map<Object?, Object?> map) {
    final rawPort = map['port'];
    final port = rawPort is int
        ? rawPort
        : int.tryParse(rawPort?.toString() ?? '') ?? 80;

    return DiscoveredPyCleanDevice(
      serviceName: map['serviceName']?.toString() ?? 'PyClean Device',
      serviceType: map['serviceType']?.toString() ?? '_pyclean._tcp.',
      host: map['host']?.toString() ?? '',
      port: port,
    );
  }
}

class PyCleanDiscovery {
  static const MethodChannel _channel = MethodChannel('pyclean/nsd');

  Future<DiscoveredPyCleanDevice?> discover() async {
    final result = await _channel.invokeMethod<Object?>('discoverPyClean');
    if (result == null) return null;

    if (result is! Map) {
      throw const FormatException(
        'Android returned an invalid PyClean discovery result.',
      );
    }

    final device = DiscoveredPyCleanDevice.fromMap(result);
    if (device.host.trim().isEmpty) {
      throw const FormatException(
        'Android discovered a PyClean service without an address.',
      );
    }

    return device;
  }
}

class Esp32Device {
  const Esp32Device({
    required this.deviceName,
    required this.type,
    required this.online,
    required this.hostname,
    required this.ip,
    required this.rssi,
    required this.uptimeMs,
    required this.freeHeap,
  });

  final String deviceName;
  final String type;
  final bool online;
  final String hostname;
  final String ip;
  final int rssi;
  final int uptimeMs;
  final int freeHeap;

  factory Esp32Device.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool asBool(dynamic value) {
      if (value is bool) return value;
      final normalized = value?.toString().trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'online';
    }

    return Esp32Device(
      deviceName: json['device_name']?.toString().trim().isNotEmpty == true
          ? json['device_name'].toString().trim()
          : 'PyClean ESP32',
      type: json['type']?.toString() ?? 'esp32',
      online: asBool(json['online']),
      hostname: json['hostname']?.toString() ?? '',
      ip: json['ip']?.toString() ?? '',
      rssi: asInt(json['rssi']),
      uptimeMs: asInt(json['uptime_ms']),
      freeHeap: asInt(json['free_heap']),
    );
  }
}

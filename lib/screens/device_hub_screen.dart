import 'package:flutter/material.dart';

import '../models/esp32_device.dart';
import '../services/esp32_api.dart';
import '../services/pyclean_discovery.dart';

class DeviceHubScreen extends StatefulWidget {
  const DeviceHubScreen({super.key});

  @override
  State<DeviceHubScreen> createState() => _DeviceHubScreenState();
}

class _DeviceHubScreenState extends State<DeviceHubScreen> {
  final PyCleanDiscovery _discovery = PyCleanDiscovery();

  Esp32Device? _device;
  DiscoveredPyCleanDevice? _discovered;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshEsp32();
  }

  Future<void> _refreshEsp32() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final discovered = await _discovery.discover();
      if (!mounted) return;

      if (discovered == null) {
        throw StateError(
          'ESP32 tidak ditemukan di jaringan lokal. '
          'Pastikan ESP32 menyala dan terhubung ke hotspot/Wi-Fi yang sama.',
        );
      }

      final api = Esp32Api(baseUrl: discovered.baseUrl);
      final device = await api.status();
      if (!mounted) return;

      setState(() {
        _discovered = discovered;
        _device = device;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatUptime(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (days > 0) return '${days}d ${hours}h ${minutes}m';
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${minutes}m ${seconds}s';
    }
    if (duration.inMinutes > 0) return '${duration.inMinutes}m ${seconds}s';
    return '${seconds}s';
  }

  String _formatHeap(int bytes) {
    if (bytes <= 0) return '0 KB';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  String _signalLabel(int rssi) {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Good';
    if (rssi >= -70) return 'Fair';
    return 'Weak';
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    final discovered = _discovered;
    final online = device?.online == true && _error == null;
    final statusColor = online
        ? const Color(0xFFA6E3A1)
        : const Color(0xFFF38BA8);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PyClean Device Hub'),
        backgroundColor: const Color(0xFF2A2A3C),
        actions: [
          IconButton(
            tooltip: 'Cari ulang perangkat',
            onPressed: _loading ? null : _refreshEsp32,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshEsp32,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'IoT Devices',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF21222C),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF313244),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.memory,
                          color: Color(0xFF89B4FA),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device?.deviceName ?? 'PyClean ESP32',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              device?.type ?? 'esp32-s3',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _loading && device == null
                                ? 'SEARCHING'
                                : online
                                    ? 'ONLINE'
                                    : 'OFFLINE',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (device != null) ...[
                    _InfoRow(
                      icon: Icons.wifi,
                      label: 'Signal',
                      value: '${device.rssi} dBm • ${_signalLabel(device.rssi)}',
                    ),
                    _InfoRow(
                      icon: Icons.schedule,
                      label: 'Uptime',
                      value: _formatUptime(device.uptimeMs),
                    ),
                    _InfoRow(
                      icon: Icons.memory_outlined,
                      label: 'Free heap',
                      value: _formatHeap(device.freeHeap),
                    ),
                    _InfoRow(
                      icon: Icons.language,
                      label: 'Hostname',
                      value: device.hostname.isEmpty
                          ? 'pyclean-esp32.local'
                          : device.hostname,
                    ),
                    _InfoRow(
                      icon: Icons.lan_outlined,
                      label: 'Current IP',
                      value: device.ip,
                    ),
                    if (discovered != null)
                      _InfoRow(
                        icon: Icons.radar,
                        label: 'Detected as',
                        value: discovered.serviceName,
                      ),
                  ] else if (_loading) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 24),
                    const Center(
                      child: Text(
                        'Mencari perangkat PyClean di jaringan lokal...',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x33F38BA8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Tidak bisa menemukan/menghubungi ESP32.\n\n$_error',
                        style: const TextStyle(
                          color: Color(0xFFF38BA8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _refreshEsp32,
                      icon: const Icon(Icons.radar),
                      label: const Text('Cari ESP32'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'PyClean sekarang mencari ESP32 otomatis di jaringan lokal. '
              'Kamu tidak perlu mengetik atau mengingat alamat IP-nya.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Colors.white38),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

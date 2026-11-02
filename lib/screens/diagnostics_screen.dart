import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/esp32_device.dart';
import '../services/connection_store.dart';
import '../services/esp32_api.dart';
import '../services/pyclean_api.dart';
import '../services/pyclean_discovery.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  static const String _appVersion = '1.0.0+1';

  static const Color _blue = Color(0xFF89B4FA);
  static const Color _green = Color(0xFFA6E3A1);
  static const Color _red = Color(0xFFF38BA8);
  static const Color _yellow = Color(0xFFF9E2AF);
  static const Color _mauve = Color(0xFFCBA6F7);
  static const Color _surface = Color(0xFF1E1E2E);
  static const Color _outline = Color(0xFF45475A);

  final ConnectionStore _connectionStore = ConnectionStore();
  final PyCleanDiscovery _discovery = PyCleanDiscovery();

  bool _running = false;
  DateTime? _lastRunAt;

  String _pcStatus = 'NOT CHECKED';
  bool? _pcOnline;
  String _pcDeviceName = 'PyClean PC';
  String _pcSavedUrl = '';
  String _pcReportedIp = '';
  String _pcAccess = '—';
  int? _pcLatencyMs;
  String _pcFriendlyError = '';
  String _pcTechnicalError = '';
  String _pcHint = 'Run diagnostics to test the saved PC endpoint.';

  String _espStatus = 'NOT CHECKED';
  bool? _espOnline;
  DiscoveredPyCleanDevice? _espDiscovered;
  Esp32Device? _espDevice;
  int? _espDiscoveryMs;
  int? _espLatencyMs;
  String _espFriendlyError = '';
  String _espTechnicalError = '';
  String _espHint = 'Run diagnostics to test NSD discovery and ESP32 HTTP status.';

  @override
  void initState() {
    super.initState();
    _loadSavedPcPreview();
  }

  Future<void> _loadSavedPcPreview() async {
    final saved = await _connectionStore.load();
    if (!mounted) return;

    setState(() {
      _pcSavedUrl = saved.serverUrl.trim();
      _pcDeviceName = saved.deviceName.trim().isEmpty
          ? 'PyClean PC'
          : saved.deviceName.trim();

      if (_pcSavedUrl.isEmpty) {
        _pcStatus = 'NOT PAIRED';
        _pcHint = 'Scan the desktop QR code from Device Hub first.';
      }
    });
  }

  Future<void> _runDiagnostics() async {
    if (_running) return;

    setState(() {
      _running = true;

      _pcLatencyMs = null;
      _pcReportedIp = '';
      _pcAccess = '—';
      _pcFriendlyError = '';
      _pcTechnicalError = '';
      _pcHint = 'Checking saved PC endpoint…';

      _espDiscoveryMs = null;
      _espLatencyMs = null;
      _espDiscovered = null;
      _espDevice = null;
      _espFriendlyError = '';
      _espTechnicalError = '';
      _espHint = 'Searching for PyClean ESP32…';
    });

    await _runPcDiagnostic();
    if (!mounted) return;

    await _runEspDiagnostic();
    if (!mounted) return;

    setState(() {
      _running = false;
      _lastRunAt = DateTime.now();
    });
  }

  Future<void> _runPcDiagnostic() async {
    final saved = await _connectionStore.load();
    if (!mounted) return;

    final url = saved.serverUrl.trim();
    final name = saved.deviceName.trim().isEmpty
        ? 'PyClean PC'
        : saved.deviceName.trim();

    setState(() {
      _pcSavedUrl = url;
      _pcDeviceName = name;
    });

    if (url.isEmpty) {
      setState(() {
        _pcOnline = null;
        _pcStatus = 'NOT PAIRED';
        _pcHint = 'No saved PC. Scan the desktop QR code from Device Hub.';
      });
      return;
    }

    final api = PyCleanApi()..setServerUrl(url);
    final timer = Stopwatch()..start();

    try {
      final status = await api.status(
        timeout: const Duration(seconds: 5),
        attempts: 1,
      );
      timer.stop();

      final deviceName = status.deviceName.trim().isEmpty
          ? name
          : status.deviceName.trim();

      final accessScope = status.shareEnabled
          ? (status.sharedName.trim().isEmpty
              ? 'Shared folder'
              : status.sharedName.trim())
          : 'Full PC';

      final access =
          '$accessScope · ${status.readOnly ? 'Read only' : 'Full access'}';

      String hint;
      final savedHost = Uri.tryParse(api.serverUrl)?.host ?? '';
      if (_isIpv4(savedHost) &&
          status.ip.trim().isNotEmpty &&
          savedHost != status.ip.trim()) {
        hint =
            'Saved endpoint $savedHost differs from Agent-reported IP '
            '${status.ip.trim()}. Scan a fresh QR code.';
      } else if (status.isSuccess) {
        hint = 'Direct PC HTTP reachability is working.';
      } else {
        hint = 'The PC responded, but PyClean Agent did not report online.';
      }

      if (!mounted) return;
      setState(() {
        _pcOnline = status.isSuccess;
        _pcStatus = status.isSuccess ? 'ONLINE' : 'RESPONDED';
        _pcDeviceName = deviceName;
        _pcLatencyMs = timer.elapsedMilliseconds;
        _pcReportedIp = status.ip.trim();
        _pcAccess = access;
        _pcHint = hint;
      });
    } catch (error) {
      timer.stop();
      if (!mounted) return;

      setState(() {
        _pcOnline = false;
        _pcStatus = _statusForError(error);
        _pcLatencyMs = timer.elapsedMilliseconds;
        _pcFriendlyError = _friendlyError(error);
        _pcTechnicalError = error.toString();
        _pcHint = _pcHintForError(error);
      });
    }
  }

  Future<void> _runEspDiagnostic() async {
    final discoveryTimer = Stopwatch()..start();

    DiscoveredPyCleanDevice? discovered;

    try {
      discovered = await _discovery.discover();
      discoveryTimer.stop();

      if (!mounted) return;

      if (discovered == null) {
        setState(() {
          _espOnline = false;
          _espStatus = 'NOT FOUND';
          _espDiscoveryMs = discoveryTimer.elapsedMilliseconds;
          _espHint =
              'NSD discovery timed out. The ESP32 may be offline, on another '
              'network, or multicast/local peer traffic may be blocked.';
        });
        return;
      }

      setState(() {
        _espDiscovered = discovered;
        _espDiscoveryMs = discoveryTimer.elapsedMilliseconds;
        _espStatus = 'DISCOVERED';
        _espHint = 'ESP32 service discovered. Checking HTTP status…';
      });

      final statusTimer = Stopwatch()..start();

      try {
        final device = await Esp32Api(
          baseUrl: discovered.baseUrl,
        ).status(
          timeout: const Duration(seconds: 4),
        );
        statusTimer.stop();

        if (!mounted) return;

        setState(() {
          _espDevice = device;
          _espOnline = device.online;
          _espStatus = device.online ? 'ONLINE' : 'RESPONDED';
          _espLatencyMs = statusTimer.elapsedMilliseconds;
          _espHint = device.online
              ? 'NSD discovery and ESP32 HTTP reachability are working.'
              : 'ESP32 responded, but did not report online.';
        });
      } catch (error) {
        statusTimer.stop();
        if (!mounted) return;

        setState(() {
          _espOnline = false;
          _espStatus = _statusForError(error);
          _espLatencyMs = statusTimer.elapsedMilliseconds;
          _espFriendlyError = _friendlyError(error);
          _espTechnicalError = error.toString();
          _espHint =
              'NSD found the ESP32, but its HTTP endpoint failed. '
              'Check routing, Wi-Fi reachability, or the ESP32 web server.';
        });
      }
    } catch (error) {
      discoveryTimer.stop();
      if (!mounted) return;

      setState(() {
        _espOnline = false;
        _espStatus = 'DISCOVERY ERROR';
        _espDiscoveryMs = discoveryTimer.elapsedMilliseconds;
        _espFriendlyError = _friendlyError(error);
        _espTechnicalError = error.toString();
        _espHint =
            'Android could not complete local service discovery. '
            'Check Wi-Fi, multicast/NSD support, and device availability.';
      });
    }
  }

  String _statusForError(Object error) {
    if (error is TimeoutException) return 'TIMEOUT';
    if (error is SocketException || error is http.ClientException) {
      return 'UNREACHABLE';
    }
    if (error is FormatException) return 'INVALID RESPONSE';
    if (error is PlatformException) return 'DISCOVERY ERROR';
    return 'FAILED';
  }

  String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return 'The device did not respond before the timeout.';
    }

    if (error is SocketException || error is http.ClientException) {
      return 'The device is unreachable on the local network.';
    }

    if (error is FormatException) {
      return 'The device returned an invalid response.';
    }

    if (error is PlatformException) {
      return error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : 'Android local service discovery failed.';
    }

    if (error is StateError) {
      return 'The device responded with an unexpected state.';
    }

    return 'The diagnostic request failed.';
  }

  String _pcHintForError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return 'Direct PC reachability failed. Check a stale QR/IP, Windows '
          'firewall/network profile, Wi-Fi client isolation, or whether both '
          'devices are on the same local network.';
    }

    if (error is FormatException) {
      return 'The saved endpoint responded with data PyClean could not parse. '
          'Scan a fresh QR code and verify the desktop Agent.';
    }

    return 'Check the PyClean Agent and run diagnostics again.';
  }

  String get _networkClue {
    if (_lastRunAt == null) {
      return 'Run diagnostics to generate a network clue.';
    }

    final hasPc = _pcSavedUrl.trim().isNotEmpty;

    if (!hasPc && _espOnline == true) {
      return 'ESP32 local discovery works. Pair a PC to test direct PC routing.';
    }

    if (!hasPc && _espOnline != true) {
      return 'Pair a PC and keep the ESP32 online for a complete local-network test.';
    }

    if (_pcOnline == true && _espOnline == true) {
      return 'PC HTTP routing and ESP32 NSD discovery are both working.';
    }

    if (_pcOnline == true && _espOnline != true) {
      return 'PC direct HTTP works, but ESP32 discovery/status does not. '
          'Check ESP32 power/Wi-Fi and multicast/NSD filtering.';
    }

    if (_pcOnline != true && _espOnline == true) {
      return 'ESP32 discovery and HTTP work, but the PC endpoint does not. '
          'Focus on the saved PC IP, Windows firewall/network profile, or the '
          'PC network interface.';
    }

    return 'Both PC reachability and ESP32 discovery failed. If both devices '
        'are known online, check network mismatch, firewall rules, or Wi-Fi '
        'client/AP isolation.';
  }

  bool _isIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;

    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0 || number > 255) {
        return false;
      }
    }

    return true;
  }

  Future<void> _copyDebugInfo() async {
    final now = _lastRunAt ?? DateTime.now();
    final discovered = _espDiscovered;
    final device = _espDevice;

    final lines = <String>[
      'PyClean Diagnostics',
      'Generated: ${now.toIso8601String()}',
      'App: PyClean Mobile $_appVersion',
      'Platform: ${Platform.operatingSystem}',
      '',
      'PC',
      'Status: $_pcStatus',
      'Device: $_pcDeviceName',
      'Saved URL: ${_pcSavedUrl.isEmpty ? '—' : _pcSavedUrl}',
      'Agent IP: ${_pcReportedIp.isEmpty ? '—' : _pcReportedIp}',
      'Latency: ${_latencyLabel(_pcLatencyMs)}',
      'Access: $_pcAccess',
      if (_pcFriendlyError.isNotEmpty) 'Error: $_pcFriendlyError',
      if (_pcTechnicalError.isNotEmpty) 'Technical: $_pcTechnicalError',
      'Hint: $_pcHint',
      '',
      'ESP32',
      'Status: $_espStatus',
      'Service: ${discovered?.serviceName ?? '—'}',
      'Endpoint: ${discovered?.baseUrl ?? '—'}',
      'Discovery: ${_latencyLabel(_espDiscoveryMs)}',
      'HTTP latency: ${_latencyLabel(_espLatencyMs)}',
      'Device IP: ${device?.ip.isNotEmpty == true ? device!.ip : '—'}',
      'Signal: ${device == null ? '—' : '${device.rssi} dBm'}',
      if (_espFriendlyError.isNotEmpty) 'Error: $_espFriendlyError',
      if (_espTechnicalError.isNotEmpty) 'Technical: $_espTechnicalError',
      'Hint: $_espHint',
      '',
      'Network clue',
      _networkClue,
    ];

    await Clipboard.setData(
      ClipboardData(text: lines.join('\n')),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Debug info copied.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _latencyLabel(int? milliseconds) {
    return milliseconds == null ? '—' : '$milliseconds ms';
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

  String _lastRunLabel() {
    final value = _lastRunAt;
    if (value == null) return 'Not run yet';

    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');

    return '$hour:$minute:$second';
  }

  Color _statusColor(String status) {
    if (status == 'ONLINE') return _green;
    if (status == 'NOT CHECKED' ||
        status == 'NOT PAIRED' ||
        status == 'NOT FOUND') {
      return Colors.white38;
    }
    if (status == 'RESPONDED' || status == 'DISCOVERED') return _yellow;
    return _red;
  }

  @override
  Widget build(BuildContext context) {
    final esp = _espDevice;
    final discovered = _espDiscovered;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Diagnostics & About',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _DiagnosticHero(
            running: _running,
            lastRunLabel: _lastRunLabel(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _runDiagnostics,
                  icon: _running
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _running ? 'Running…' : 'Run diagnostics',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed:
                    _running || _lastRunAt == null ? null : _copyDebugInfo,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle('APP'),
          _DiagnosticCard(
            accent: _blue,
            icon: Icons.info_outline_rounded,
            title: 'PyClean Mobile',
            status: _appVersion,
            statusColor: _blue,
            children: const [
              _DiagnosticRow(
                label: 'Platform',
                value: 'Android',
              ),
              _DiagnosticRow(
                label: 'Stack',
                value: 'Flutter · Local-first',
              ),
              _DiagnosticRow(
                label: 'Devices',
                value: 'Windows · Android · ESP32',
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _SectionTitle('PC'),
          _DiagnosticCard(
            accent: _blue,
            icon: Icons.computer_rounded,
            title: _pcDeviceName,
            status: _pcStatus,
            statusColor: _statusColor(_pcStatus),
            children: [
              _DiagnosticRow(
                label: 'Endpoint',
                value: _pcSavedUrl.isEmpty ? 'Not paired' : _pcSavedUrl,
              ),
              _DiagnosticRow(
                label: 'Latency',
                value: _latencyLabel(_pcLatencyMs),
              ),
              _DiagnosticRow(
                label: 'Agent IP',
                value: _pcReportedIp.isEmpty ? '—' : _pcReportedIp,
              ),
              _DiagnosticRow(
                label: 'Access',
                value: _pcAccess,
              ),
              _HintBox(
                text: _pcHint,
                color: _pcOnline == true ? _green : _yellow,
              ),
              if (_pcFriendlyError.isNotEmpty)
                _ErrorBox(
                  message: _pcFriendlyError,
                  technical: _pcTechnicalError,
                ),
            ],
          ),
          const SizedBox(height: 18),
          const _SectionTitle('ESP32'),
          _DiagnosticCard(
            accent: _mauve,
            icon: Icons.memory_rounded,
            title: esp?.deviceName ?? 'PyClean ESP32',
            status: _espStatus,
            statusColor: _statusColor(_espStatus),
            children: [
              _DiagnosticRow(
                label: 'Service',
                value: discovered?.serviceName ?? '—',
              ),
              _DiagnosticRow(
                label: 'Endpoint',
                value: discovered?.baseUrl ?? '—',
              ),
              _DiagnosticRow(
                label: 'Discovery',
                value: _latencyLabel(_espDiscoveryMs),
              ),
              _DiagnosticRow(
                label: 'HTTP latency',
                value: _latencyLabel(_espLatencyMs),
              ),
              _DiagnosticRow(
                label: 'Device IP',
                value: esp?.ip.isNotEmpty == true ? esp!.ip : '—',
              ),
              _DiagnosticRow(
                label: 'Signal',
                value: esp == null ? '—' : '${esp.rssi} dBm',
              ),
              _DiagnosticRow(
                label: 'Uptime',
                value: esp == null ? '—' : _formatUptime(esp.uptimeMs),
              ),
              _DiagnosticRow(
                label: 'Free heap',
                value: esp == null ? '—' : _formatHeap(esp.freeHeap),
              ),
              _HintBox(
                text: _espHint,
                color: _espOnline == true ? _green : _yellow,
              ),
              if (_espFriendlyError.isNotEmpty)
                _ErrorBox(
                  message: _espFriendlyError,
                  technical: _espTechnicalError,
                ),
            ],
          ),
          const SizedBox(height: 18),
          const _SectionTitle('NETWORK CLUE'),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _outline.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.network_check_rounded,
                  color: _blue,
                  size: 22,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    _networkClue,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('ABOUT'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _outline.withValues(alpha: 0.45),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PyClean',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Local-first device management for direct file access '
                  'and nearby device monitoring.',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Windows · Android · ESP32',
                  style: TextStyle(
                    color: _blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticHero extends StatelessWidget {
  const _DiagnosticHero({
    required this.running,
    required this.lastRunLabel,
  });

  final bool running;
  final String lastRunLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF23233A),
            Color(0xFF1A1A2A),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0x3345475A),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0x1A89B4FA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.troubleshoot_rounded,
              color: Color(0xFF89B4FA),
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Network Diagnostics',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  running
                      ? 'Testing local devices…'
                      : 'Last run: $lastRunLabel',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 2,
        bottom: 8,
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({
    required this.accent,
    required this.icon,
    required this.title,
    required this.status,
    required this.statusColor,
    required this.children,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String status;
  final Color statusColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _DiagnosticsScreenState._surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _DiagnosticsScreenState._outline.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(
                  icon,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(
                text: status,
                color: statusColor,
              ),
            ],
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _HintBox extends StatelessWidget {
  const _HintBox({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: color.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white60,
          fontSize: 10,
          height: 1.4,
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({
    required this.message,
    required this.technical,
  });

  final String message;
  final String technical;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: const Color(0x0FF38BA8),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: const Color(0x33F38BA8),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        dense: true,
        leading: const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFF38BA8),
          size: 18,
        ),
        title: Text(
          message,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: const Text(
          'Technical details',
          style: TextStyle(
            color: Colors.white30,
            fontSize: 9,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              technical,
              style: const TextStyle(
                color: Colors.white38,
                fontFamily: 'monospace',
                fontSize: 9,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

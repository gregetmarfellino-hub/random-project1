import 'dart:async';

import 'package:flutter/material.dart';

import '../models/esp32_device.dart';
import '../services/connection_store.dart';
import '../services/esp32_api.dart';
import '../services/pyclean_api.dart';
import '../services/pyclean_discovery.dart';
import 'diagnostics_screen.dart';
import 'qr_scanner_page.dart';
import 'remote_home_screen.dart';

class DeviceHubScreen extends StatefulWidget {
  const DeviceHubScreen({super.key});

  @override
  State<DeviceHubScreen> createState() => _DeviceHubScreenState();
}

class _DeviceHubScreenState extends State<DeviceHubScreen>
    with WidgetsBindingObserver {
  static const Duration _pollInterval = Duration(seconds: 1);
  static const Duration _espRediscoveryInterval = Duration(seconds: 10);
  static const int _offlineFailureThreshold = 2;

  static const Color _blue = Color(0xFF89B4FA);
  static const Color _green = Color(0xFFA6E3A1);
  static const Color _red = Color(0xFFF38BA8);
  static const Color _yellow = Color(0xFFF9E2AF);
  static const Color _mauve = Color(0xFFCBA6F7);
  static const Color _surface = Color(0xFF1E1E2E);
  static const Color _surfaceRaised = Color(0xFF242435);
  static const Color _outline = Color(0xFF45475A);

  final ConnectionStore _connectionStore = ConnectionStore();
  final PyCleanApi _pcApi = PyCleanApi();
  final PyCleanDiscovery _discovery = PyCleanDiscovery();

  Timer? _liveTimer;

  final List<_HubActivity> _activity = <_HubActivity>[];

  String _pcServerUrl = '';
  String _pcDeviceName = 'PyClean PC';
  String _pcLastPath = '';
  String _pcIp = '';
  int _pcPort = 0;
  bool _pcShareEnabled = false;
  bool _pcReadOnly = false;
  String _pcSharedName = '';
  bool? _pcOnline;
  bool _pcBusy = false;
  DateTime? _pcUpdatedAt;
  int _pcFailureCount = 0;
  String? _pcError;

  Esp32Api? _espApi;
  Esp32Device? _espDevice;
  DiscoveredPyCleanDevice? _espDiscovered;
  bool? _espOnline;
  bool _espBusy = false;
  DateTime? _espUpdatedAt;
  String? _espError;
  int _espFailureCount = 0;
  DateTime? _lastEspDiscoveryAttempt;
  int? _lastEspUptimeMs;

  bool _screenActive = true;
  bool _manualRefreshBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLiveTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _screenActive = true;
      _startLiveTimer();
      _refreshAll();
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _screenActive = false;
      _stopLiveTimer();
    }
  }

  Future<void> _bootstrap() async {
    await _loadSavedPc();
    if (!mounted) return;

    await Future.wait<void>([
      _refreshPcStatus(),
      _refreshEsp32(),
    ]);

    if (!mounted) return;
    _startLiveTimer();
  }

  void _startLiveTimer() {
    if (!_screenActive || !mounted) return;

    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(_pollInterval, (_) {
      _pollLiveStatus();
    });
  }

  void _stopLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  Future<void> _pollLiveStatus() async {
    if (!_screenActive || !mounted) return;

    await Future.wait<void>([
      _refreshPcStatus(),
      _refreshEsp32(),
    ]);
  }

  void _recordActivity({
    required String message,
    required IconData icon,
    required Color color,
  }) {
    if (!mounted) return;

    setState(() {
      _activity.insert(
        0,
        _HubActivity(
          message: message,
          icon: icon,
          color: color,
          at: DateTime.now(),
        ),
      );

      if (_activity.length > 6) {
        _activity.removeRange(6, _activity.length);
      }
    });
  }

  bool _espRediscoveryDue() {
    final last = _lastEspDiscoveryAttempt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _espRediscoveryInterval;
  }

  Future<void> _loadSavedPc() async {
    final saved = await _connectionStore.load();
    if (!mounted) return;

    setState(() {
      _pcServerUrl = saved.serverUrl.trim();
      _pcDeviceName = saved.deviceName.trim().isEmpty
          ? 'PyClean PC'
          : saved.deviceName.trim();
      _pcLastPath = saved.lastPath.trim();

      if (_pcServerUrl.isEmpty) {
        _pcOnline = null;
        _pcIp = '';
        _pcPort = 0;
        _pcShareEnabled = false;
        _pcReadOnly = false;
        _pcSharedName = '';
      }
    });

    if (_pcServerUrl.isNotEmpty) {
      _pcApi.setServerUrl(_pcServerUrl);
    }
  }

  Future<void> _refreshPcStatus() async {
    if (_pcBusy || _pcServerUrl.trim().isEmpty || !mounted) return;

    _pcBusy = true;
    _pcApi.setServerUrl(_pcServerUrl);
    final wasOnline = _pcOnline;

    try {
      final status = await _pcApi.status(
        timeout: const Duration(seconds: 2),
      );
      if (!mounted) return;

      final deviceName = status.deviceName.trim().isEmpty
          ? _pcDeviceName
          : status.deviceName.trim();

      _pcFailureCount = 0;

      setState(() {
        _pcOnline = status.isSuccess;
        _pcDeviceName = deviceName;
        _pcIp = status.ip.trim();
        _pcPort = status.port;
        _pcShareEnabled = status.shareEnabled;
        _pcReadOnly = status.readOnly;
        _pcSharedName = status.sharedName.trim();
        _pcUpdatedAt = DateTime.now();
        _pcError = status.isSuccess
            ? null
            : 'The Agent responded but did not report an online status.';
      });

      if (status.isSuccess && wasOnline != true) {
        _recordActivity(
          message: '$deviceName is online',
          icon: Icons.computer_rounded,
          color: _green,
        );
      }

      if (status.isSuccess) {
        await _connectionStore.saveConnection(
          serverUrl: _pcApi.serverUrl,
          deviceName: deviceName,
        );
      }
    } catch (e) {
      debugPrint(
        'PyClean hub status failed: ${pyCleanTechnicalDetails(e)}',
      );
      if (!mounted) return;

      _pcFailureCount += 1;
      final shouldMarkOffline =
          _pcFailureCount >= _offlineFailureThreshold;

      setState(() {
        if (shouldMarkOffline) {
          _pcOnline = false;
          _pcError =
              '${pyCleanConnectionMessage(e)} '
              'If the network changed, scan a fresh QR code.';
        }
        _pcUpdatedAt = DateTime.now();
      });

      if (shouldMarkOffline && wasOnline == true) {
        _recordActivity(
          message: '$_pcDeviceName went offline',
          icon: Icons.link_off_rounded,
          color: _red,
        );
      }
    } finally {
      _pcBusy = false;
    }
  }

  Future<void> _refreshEsp32({bool forceDiscovery = false}) async {
    if (_espBusy || !mounted) return;

    if (_espApi == null && !forceDiscovery && !_espRediscoveryDue()) {
      return;
    }

    _espBusy = true;
    final wasOnline = _espOnline;

    try {
      if (_espApi == null || forceDiscovery) {
        _lastEspDiscoveryAttempt = DateTime.now();

        final discovered = await _discovery.discover();
        if (!mounted) return;

        if (discovered == null) {
          _espFailureCount = _offlineFailureThreshold;
          setState(() {
            _espOnline = false;
            _espUpdatedAt = DateTime.now();
            _espError = 'Waiting for PyClean ESP32 on the local network.';
            _espApi = null;
          });

          if (wasOnline == true) {
            _recordActivity(
              message: 'PyClean ESP32 disappeared from the network',
              icon: Icons.portable_wifi_off_rounded,
              color: _red,
            );
          }
          return;
        }

        _espDiscovered = discovered;
        _espApi = Esp32Api(baseUrl: discovered.baseUrl);
      }

      final device = await _espApi!.status(
        timeout: const Duration(seconds: 2),
      );
      if (!mounted) return;

      final previousUptime = _lastEspUptimeMs;
      final restarted = previousUptime != null &&
          device.uptimeMs + 2000 < previousUptime;

      _espFailureCount = 0;
      _lastEspUptimeMs = device.uptimeMs;

      setState(() {
        _espDevice = device;
        _espOnline = device.online;
        _espUpdatedAt = DateTime.now();
        _espError = null;
      });

      if (restarted) {
        _recordActivity(
          message: '${device.deviceName} restarted',
          icon: Icons.restart_alt_rounded,
          color: _yellow,
        );
      } else if (device.online && wasOnline != true) {
        _recordActivity(
          message: '${device.deviceName} is online',
          icon: Icons.memory_rounded,
          color: _green,
        );
      }
    } catch (_) {
      if (!mounted) return;

      _espFailureCount += 1;
      final shouldMarkOffline =
          _espFailureCount >= _offlineFailureThreshold;

      setState(() {
        if (shouldMarkOffline) {
          _espOnline = false;
          _espError = 'Device lost. Rediscovery is automatic.';
          _espApi = null;
        }
        _espUpdatedAt = DateTime.now();
      });

      if (shouldMarkOffline && wasOnline == true) {
        _recordActivity(
          message: '${_espDevice?.deviceName ?? 'PyClean ESP32'} went offline',
          icon: Icons.portable_wifi_off_rounded,
          color: _red,
        );
      }
    } finally {
      _espBusy = false;
    }
  }

  Future<void> _refreshAll() async {
    if (_manualRefreshBusy || !mounted) return;

    setState(() {
      _manualRefreshBusy = true;
    });

    await _loadSavedPc();
    await Future.wait<void>([
      _refreshPcStatus(),
      _refreshEsp32(),
    ]);

    if (!mounted) return;
    setState(() {
      _manualRefreshBusy = false;
    });
  }

  Future<void> _scanPc() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScannerPage(),
      ),
    );

    if (!mounted || result == null || result.trim().isEmpty) return;

    final scannedUrl = result.trim();
    final candidate = PyCleanApi()..setServerUrl(scannedUrl);

    _showMessage('Checking scanned PyClean PC...', _blue);

    try {
      final status = await candidate.status(
        timeout: const Duration(seconds: 10),
        attempts: 2,
      );

      if (!status.isSuccess) {
        throw StateError('PyClean PC did not report an online status.');
      }

      final deviceName = status.deviceName.trim().isEmpty
          ? 'PyClean PC'
          : status.deviceName.trim();

      await _connectionStore.saveConnection(
        serverUrl: candidate.serverUrl,
        deviceName: deviceName,
      );

      if (!mounted) return;

      setState(() {
        _pcServerUrl = candidate.serverUrl;
        _pcDeviceName = deviceName;
        _pcIp = status.ip.trim();
        _pcPort = status.port;
        _pcShareEnabled = status.shareEnabled;
        _pcReadOnly = status.readOnly;
        _pcSharedName = status.sharedName.trim();
        _pcOnline = true;
        _pcUpdatedAt = DateTime.now();
        _pcFailureCount = 0;
        _pcError = null;
      });

      _pcApi.setServerUrl(candidate.serverUrl);
      _recordActivity(
        message: 'Paired with $deviceName',
        icon: Icons.qr_code_scanner_rounded,
        color: _blue,
      );
      _showMessage('$deviceName connected.', _green);
    } catch (e) {
      debugPrint(
        'PyClean QR pairing failed: ${pyCleanTechnicalDetails(e)}',
      );
      if (!mounted) return;
      _showMessage(pyCleanConnectionMessage(e), _red);
    }
  }

  Future<void> _openPcRemote() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const RemoteHomeScreen(),
      ),
    );

    if (!mounted) return;
    await _loadSavedPc();
    await _refreshPcStatus();
  }

  Future<void> _openDiagnostics() async {
    // Avoid racing the Hub's 1-second polling/ESP32 rediscovery against
    // the explicit probes on the diagnostics screen.
    _stopLiveTimer();

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const DiagnosticsScreen(),
      ),
    );

    if (!mounted) return;

    _startLiveTimer();
    await _refreshAll();
  }

  void _showMessage(String message, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
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

  String _updatedLabel(DateTime? value) {
    if (value == null) return 'Not checked yet';

    final seconds = DateTime.now().difference(value).inSeconds;
    if (seconds < 5) return 'Updated just now';
    if (seconds < 60) return 'Updated ${seconds}s ago';

    final minutes = seconds ~/ 60;
    return 'Updated ${minutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            _PyCleanMark(),
            SizedBox(width: 10),
            Text(
              'PyClean',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Diagnostics & About',
            onPressed: _openDiagnostics,
            icon: const Icon(Icons.troubleshoot_rounded),
          ),
          IconButton(
            tooltip: 'Scan PyClean PC',
            onPressed: _scanPc,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            tooltip: 'Refresh devices',
            onPressed: _manualRefreshBusy ? null : _refreshAll,
            icon: _manualRefreshBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildHero(),
            const SizedBox(height: 24),
            const _SectionHeader(
              title: 'MY DEVICES',
              subtitle: 'Live local status',
            ),
            const SizedBox(height: 10),
            _buildPcCard(),
            const SizedBox(height: 12),
            _buildEspCard(),
            const SizedBox(height: 24),
            const _SectionHeader(
              title: 'RECENT ACTIVITY',
              subtitle: 'This session',
            ),
            const SizedBox(height: 10),
            _buildActivityCard(),
            const SizedBox(height: 18),
            _buildLiveFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    final onlineCount = (_pcOnline == true ? 1 : 0) + (_espOnline == true ? 1 : 0);

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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x3345475A)),
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
              Icons.hub_rounded,
              color: _blue,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Device Hub',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$onlineCount of 2 devices online',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x1AA6E3A1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x55A6E3A1)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulseDot(color: _green),
                SizedBox(width: 7),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: _green,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPcCard() {
    final hasPc = _pcServerUrl.isNotEmpty;
    final online = _pcOnline == true;
    final reconnecting = hasPc && online && _pcFailureCount > 0;
    final status = !hasPc
        ? 'NOT PAIRED'
        : _pcOnline == null
            ? 'CHECKING'
            : reconnecting
                ? 'RECONNECTING'
                : online
                    ? 'ONLINE'
                    : 'OFFLINE';

    final statusColor = !hasPc
        ? Colors.white38
        : _pcOnline == null || reconnecting
            ? _yellow
            : online
                ? _green
                : _red;

    final networkLabel = _pcIp.isNotEmpty
        ? _pcPort > 0
            ? '$_pcIp:$_pcPort'
            : _pcIp
        : _pcServerUrl;

    final accessScope = _pcShareEnabled
        ? (_pcSharedName.isEmpty ? 'Shared folder' : _pcSharedName)
        : 'Full PC';

    final accessLabel =
        '$accessScope · ${_pcReadOnly ? 'Read only' : 'Full access'}';

    return _DeviceCard(
      accent: _blue,
      icon: Icons.computer_rounded,
      title: hasPc ? _pcDeviceName : 'PyClean PC',
      subtitle: 'Windows PC',
      status: status,
      statusColor: statusColor,
      updatedLabel: _updatedLabel(_pcUpdatedAt),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPc) ...[
            _MetricRow(
              icon: Icons.lan_outlined,
              label: 'Network',
              value: networkLabel.isEmpty ? 'Saved connection' : networkLabel,
            ),
            _MetricRow(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Access',
              value: accessLabel,
            ),
            _MetricRow(
              icon: Icons.folder_outlined,
              label: 'Last folder',
              value: _pcLastPath.isEmpty ? 'No folder opened yet' : _pcLastPath,
            ),
            if (_pcOnline == false &&
                _pcError != null &&
                _pcError!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _red.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 17,
                        color: _red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pcError!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 12),
              child: Text(
                'Scan the desktop QR code to add a PC.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: hasPc ? _openPcRemote : _scanPc,
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: const Color(0xFF11111B),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    hasPc ? Icons.folder_open_rounded : Icons.qr_code_scanner_rounded,
                    size: 19,
                  ),
                  label: Text(
                    hasPc ? 'Open files' : 'Scan PC',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (hasPc) ...[
                const SizedBox(width: 9),
                _SquareActionButton(
                  tooltip: 'Scan another PC',
                  icon: Icons.qr_code_scanner_rounded,
                  onPressed: _scanPc,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEspCard() {
    final device = _espDevice;
    final online = _espOnline == true;
    final reconnecting = online && _espFailureCount > 0;
    final status = _espOnline == null
        ? 'DISCOVERING'
        : reconnecting
            ? 'RECONNECTING'
            : online
                ? 'ONLINE'
                : 'OFFLINE';
    final statusColor = _espOnline == null || reconnecting
        ? _yellow
        : online
            ? _green
            : _red;

    return _DeviceCard(
      accent: _mauve,
      icon: Icons.memory_rounded,
      title: device?.deviceName ?? 'PyClean ESP32',
      subtitle: device?.type ?? 'ESP32-S3',
      status: status,
      statusColor: statusColor,
      updatedLabel: _updatedLabel(_espUpdatedAt),
      child: Column(
        children: [
          if (device != null) ...[
            _MetricRow(
              icon: Icons.wifi_rounded,
              label: 'Signal',
              value: '${device.rssi} dBm • ${_signalLabel(device.rssi)}',
            ),
            _MetricRow(
              icon: Icons.schedule_rounded,
              label: 'Uptime',
              value: _formatUptime(device.uptimeMs),
            ),
            _MetricRow(
              icon: Icons.memory_outlined,
              label: 'Free heap',
              value: _formatHeap(device.freeHeap),
            ),
            _MetricRow(
              icon: Icons.lan_outlined,
              label: 'Network',
              value: device.ip.isEmpty ? 'Waiting for address' : device.ip,
            ),
          ] else ...[
            const SizedBox(height: 4),
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Color(0x2245475A),
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Searching for a PyClean ESP32 on the local network…',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (_espError != null && !online) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.autorenew_rounded,
                    size: 15,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _espError!,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_espDiscovered != null && device != null) ...[
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Discovered as ${_espDiscovered!.serviceName}',
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityCard() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _outline.withValues(alpha: 0.45)),
      ),
      child: _activity.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: Colors.white30,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Waiting for device events…',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < _activity.length; i++) ...[
                  _ActivityRow(
                    activity: _activity[i],
                    timeLabel: _updatedLabel(_activity[i].at)
                        .replaceFirst('Updated ', ''),
                  ),
                  if (i != _activity.length - 1)
                    const Divider(
                      height: 1,
                      indent: 52,
                      color: Color(0x2245475A),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _buildLiveFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x99181825),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x2245475A)),
      ),
      child: const Row(
        children: [
          Icon(Icons.bolt_rounded, size: 17, color: _green),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Live status • 1s refresh • automatic ESP32 rediscovery',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubActivity {
  const _HubActivity({
    required this.message,
    required this.icon,
    required this.color,
    required this.at,
  });

  final String message;
  final IconData icon;
  final Color color;
  final DateTime at;
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.activity,
    required this.timeLabel,
  });

  final _HubActivity activity;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: activity.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              activity.icon,
              size: 15,
              color: activity.color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              activity.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            timeLabel,
            style: const TextStyle(
              color: Colors.white24,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PyCleanMark extends StatelessWidget {
  const _PyCleanMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0x1A89B4FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x4489B4FA)),
      ),
      child: const Icon(
        Icons.auto_awesome_rounded,
        size: 18,
        color: Color(0xFF89B4FA),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.35,
            ),
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white30,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
    required this.updatedLabel,
    required this.child,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final Color statusColor;
  final String updatedLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _DeviceHubScreenState._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _DeviceHubScreenState._outline.withValues(alpha: 0.55)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Icon(icon, color: accent, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(
                label: status,
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 55),
            child: Text(
              updatedLabel,
              style: const TextStyle(
                color: Colors.white24,
                fontSize: 9.5,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Container(
            height: 1,
            color: const Color(0x2245475A),
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
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
      padding: const EdgeInsets.symmetric(vertical: 5.5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white30),
          const SizedBox(width: 9),
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

class _SquareActionButton extends StatelessWidget {
  const _SquareActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _DeviceHubScreenState._surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x5545475A)),
            ),
            child: Icon(icon, size: 20, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

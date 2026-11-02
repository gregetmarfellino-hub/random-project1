import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/connection_store.dart';
import '../services/pyclean_api.dart';
import '../widgets/ar_hologram_widget.dart';
import '../widgets/remote_folder_picker.dart';
import 'device_hub_screen.dart';
import 'qr_scanner_page.dart';

class RemoteHomeScreen extends StatefulWidget {
  const RemoteHomeScreen({super.key});

  @override
  State<RemoteHomeScreen> createState() => _RemoteHomeScreenState();
}

class _RemoteHomeScreenState extends State<RemoteHomeScreen> {
  final PyCleanApi _api = PyCleanApi();
  final ConnectionStore _connectionStore = ConnectionStore();

  bool isConnected = false;
  bool isCheckingSavedPc = false;
  bool isConnectingToPc = false;
  bool isReconnectingToPc = false;
  bool? savedPcOnline;
  String? savedPcConnectionHint;

  String savedServerUrl = '';
  String savedDeviceName = 'PyClean PC';
  String savedLastPath = '';

  bool pcShareEnabled = false;
  String pcSharedRoot = '';
  String pcSharedName = '';
  bool pcReadOnly = false;
  bool pcCanDownload = true;
  bool pcCanUpload = true;
  bool pcCanRename = true;
  bool pcCanMove = true;
  bool pcCanDelete = true;
  bool pcCanSort = true;

  String currentPath = "";
  String parentPath = "";

  List allFileItems = [];
  List filteredFileItems = [];

  bool isLoadingFiles = false;

  bool isTransferBusy = false;
  bool isTransferCancelling = false;
  String transferName = '';
  _TransferDirection? transferDirection;
  int transferBytes = 0;
  int transferTotalBytes = 0;
  double transferBytesPerSecond = 0;
  DateTime? _transferStartedAt;
  DateTime? _lastTransferUiUpdate;
  PyCleanTransferController? _transferController;
  final List<_TransferHistoryItem> transferHistory = <_TransferHistoryItem>[];

  bool isSelectionMode = false;
  bool isBatchBusy = false;
  final Set<String> selectedPaths = <String>{};

  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedConnection();
  }

  @override
  void dispose() {
    _transferController?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void _applyServerAccess(ServerStatusResult status) {
    pcShareEnabled = status.shareEnabled;
    pcSharedRoot = status.sharedRoot;
    pcSharedName = status.sharedName;
    pcReadOnly = status.readOnly;
    pcCanDownload = status.canDownload;
    pcCanUpload = status.canUpload;
    pcCanRename = status.canRename;
    pcCanMove = status.canMove;
    pcCanDelete = status.canDelete;
    pcCanSort = status.canSort;

    if (!pcCanMove && !pcCanDelete) {
      selectedPaths.clear();
      isSelectionMode = false;
      isBatchBusy = false;
    }
  }

  String get _displayCurrentPath {
    if (!pcShareEnabled || pcSharedRoot.trim().isEmpty) {
      return currentPath;
    }

    final root = pcSharedRoot.replaceAll(r'\', '/');
    final current = currentPath.replaceAll(r'\', '/');

    if (current.toLowerCase() == root.toLowerCase()) {
      return '/';
    }

    final prefix = root.endsWith('/') ? root : '$root/';
    if (current.toLowerCase().startsWith(prefix.toLowerCase())) {
      return '/${current.substring(prefix.length)}';
    }

    return currentPath;
  }

  String get _accessLabel {
    if (pcReadOnly) return 'READ ONLY';
    if (pcShareEnabled) return 'SHARED';
    return 'FULL ACCESS';
  }

  bool get _canSelectItems => pcCanMove || pcCanDelete;

  Future<void> _loadSavedConnection() async {
    final saved = await _connectionStore.load();
    if (!mounted) return;

    setState(() {
      savedServerUrl = saved.serverUrl;
      savedDeviceName = saved.deviceName;
      savedLastPath = saved.lastPath;
    });

    if (saved.exists) {
      await refreshSavedPcStatus();
    }
  }

  Future<void> refreshSavedPcStatus() async {
    if (savedServerUrl.trim().isEmpty) return;

    setState(() {
      isCheckingSavedPc = true;
      savedPcConnectionHint = null;
    });

    _api.setServerUrl(savedServerUrl);

    try {
      final status = await _api.status(
        timeout: const Duration(seconds: 4),
      );
      if (!mounted) return;

      setState(() {
        savedPcOnline = status.isSuccess;
        _applyServerAccess(status);
        savedPcConnectionHint = status.isSuccess
            ? null
            : 'PyClean Agent is offline.';
        if (status.deviceName.trim().isNotEmpty) {
          savedDeviceName = status.deviceName;
        }
      });

      if (status.isSuccess) {
        await _connectionStore.saveConnection(
          serverUrl: _api.serverUrl,
          deviceName: savedDeviceName,
        );
      }
    } catch (e) {
      debugPrint(
        'PyClean saved-PC status failed: ${pyCleanTechnicalDetails(e)}',
      );
      if (!mounted) return;
      setState(() {
        savedPcOnline = false;
        savedPcConnectionHint =
            '${pyCleanConnectionMessage(e)} '
            'If the PC changed networks, scan a fresh QR code.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isCheckingSavedPc = false;
        });
      }
    }
  }

  Future<void> connectToServer(
    String url, {
    String? preferredPath,
    bool reconnecting = false,
  }) async {
    _api.setServerUrl(url);

    setState(() {
      isConnectingToPc = !reconnecting;
      isReconnectingToPc = reconnecting;
      savedPcConnectionHint = null;
    });

    try {
      final status = await _api.status(
        timeout: const Duration(seconds: 10),
        attempts: 2,
      );

      if (!status.isSuccess) {
        throw StateError('PyClean server is not online');
      }

      final deviceName = status.deviceName.trim().isEmpty
          ? 'PyClean PC'
          : status.deviceName.trim();

      await _connectionStore.saveConnection(
        serverUrl: _api.serverUrl,
        deviceName: deviceName,
      );

      if (!mounted) return;

      setState(() {
        isConnected = true;
        savedServerUrl = _api.serverUrl;
        savedDeviceName = deviceName;
        savedPcOnline = true;
        _applyServerAccess(status);
        savedPcConnectionHint = null;
        isConnectingToPc = false;
        isReconnectingToPc = false;
      });

      final targetPath = status.shareEnabled
          ? null
          : preferredPath?.trim();

      await fetchDirectory(
        targetPath == null || targetPath.isEmpty ? null : targetPath,
      );
    } catch (e) {
      debugPrint(
        'PyClean connect failed: ${pyCleanTechnicalDetails(e)}',
      );
      if (!mounted) return;

      final message = pyCleanConnectionMessage(e);
      final staleHint = reconnecting
          ? ' If the network changed, scan a fresh QR code.'
          : '';

      setState(() {
        isConnected = false;
        savedPcOnline = false;
        isConnectingToPc = false;
        isReconnectingToPc = false;
        savedPcConnectionHint = '$message$staleHint';
      });

      showSnackBar(
        '$message$staleHint',
        Colors.red,
      );
    }
  }

  Future<void> reconnectSavedPc() async {
    if (savedServerUrl.trim().isEmpty) return;

    await connectToServer(
      savedServerUrl,
      preferredPath: savedLastPath,
      reconnecting: true,
    );
  }

  String formatBytes(dynamic bytes) {
    if (bytes == null) return '0 B';

    int b = int.tryParse(bytes.toString()) ?? 0;

    if (b <= 0) return '0 B';

    const suffixes = ["B", "KB", "MB", "GB", "TB"];

    var i = (log(b) / log(1024)).floor();

    if (i >= suffixes.length) {
      i = suffixes.length - 1;
    }

    return '${(b / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future fetchDirectory(String? path) async {
    if (!_api.isConfigured) return;

    setState(() {
      isLoadingFiles = true;
    });

    try {
      final result = await _api.browse(path);

      if (result.isSuccess) {
        setState(() {
          currentPath = result.currentPath;
          parentPath = result.parentPath;

          allFileItems = result.items;
          filteredFileItems = allFileItems;

          searchController.clear();

          isLoadingFiles = false;
          savedLastPath = result.currentPath;
        });

        await _connectionStore.saveLastPath(result.currentPath);
      } else {
        showSnackBar(
          "Could not open this folder.",
          Colors.red,
        );

        setState(() {
          isLoadingFiles = false;
        });
      }
    } catch (e) {
      showSnackBar(
        "Connection failed.",
        Colors.red,
      );

      setState(() {
        isLoadingFiles = false;
      });
    }
  }

  void filterSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        filteredFileItems = allFileItems;
      });
    } else {
      setState(() {
        filteredFileItems = allFileItems.where((item) {
          final name =
              (item['name'] ?? '').toString().toLowerCase();

          return name.contains(
            query.toLowerCase(),
          );
        }).toList();
      });
    }
  }

  List<Map> get selectedItems {
    final items = <Map>[];

    for (final item in allFileItems) {
      if (item is! Map) continue;

      final path = (item['path'] ?? '').toString();
      if (selectedPaths.contains(path)) {
        items.add(item);
      }
    }

    return items;
  }

  void enterSelectionMode([Map? firstItem]) {
    if (isBatchBusy || !_canSelectItems) return;

    setState(() {
      isSelectionMode = true;

      if (firstItem != null) {
        final path = (firstItem['path'] ?? '').toString();
        if (path.isNotEmpty) {
          selectedPaths.add(path);
        }
      }
    });
  }

  void toggleSelection(Map item) {
    if (isBatchBusy) return;

    final path = (item['path'] ?? '').toString();
    if (path.isEmpty) return;

    setState(() {
      isSelectionMode = true;
      if (!selectedPaths.add(path)) {
        selectedPaths.remove(path);
      }
    });
  }

  void selectAllVisible() {
    if (isBatchBusy) return;

    setState(() {
      isSelectionMode = true;
      for (final item in filteredFileItems) {
        if (item is! Map) continue;
        final path = (item['path'] ?? '').toString();
        if (path.isNotEmpty) {
          selectedPaths.add(path);
        }
      }
    });
  }

  void clearSelection() {
    setState(() {
      selectedPaths.clear();
      isSelectionMode = false;
      isBatchBusy = false;
    });
  }

  Future<void> moveSelectedItems() async {
    if (!pcCanMove) return;

    final items = selectedItems;
    if (items.isEmpty || isBatchBusy) return;

    final String? targetDirectory = await showDialog<String>(
      context: context,
      builder: (_) => RemoteFolderPickerDialog(
        api: _api,
        initialPath: currentPath,
      ),
    );

    if (!mounted || targetDirectory == null || targetDirectory.trim().isEmpty) {
      return;
    }

    setState(() {
      isBatchBusy = true;
    });

    int moved = 0;
    int failed = 0;

    for (final item in items) {
      final path = (item['path'] ?? '').toString();
      if (path.isEmpty) {
        failed++;
        continue;
      }

      try {
        final result = await _api.moveItem(
          itemPath: path,
          targetDirectory: targetDirectory,
        );

        if (result.isSuccess) {
          moved++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;

    clearSelection();
    await fetchDirectory(currentPath);

    if (!mounted) return;

    showSnackBar(
      failed == 0
          ? 'Moved $moved item(s).'
          : 'Moved $moved; $failed failed.',
      failed == 0 ? Colors.green : Colors.orange,
    );
  }

  Future<void> deleteSelectedItems() async {
    if (!pcCanDelete) return;

    final items = selectedItems;
    if (items.isEmpty || isBatchBusy) return;

    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete selected items?'),
            content: Text(
              '${items.length} item(s) will be permanently deleted from the PC.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() {
      isBatchBusy = true;
    });

    int deleted = 0;
    int failed = 0;

    for (final item in items) {
      final path = (item['path'] ?? '').toString();
      if (path.isEmpty) {
        failed++;
        continue;
      }

      try {
        final result = await _api.deleteItem(path);
        if (result.isSuccess) {
          deleted++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;

    clearSelection();
    await fetchDirectory(currentPath);

    if (!mounted) return;

    showSnackBar(
      failed == 0
          ? 'Deleted $deleted item(s).'
          : 'Deleted $deleted; $failed failed.',
      failed == 0 ? Colors.green : Colors.orange,
    );
  }

  void _beginTransfer(
    _TransferDirection direction,
    String name,
  ) {
    _transferController?.cancel();

    setState(() {
      isTransferBusy = true;
      isTransferCancelling = false;
      transferDirection = direction;
      transferName = name;
      transferBytes = 0;
      transferTotalBytes = 0;
      transferBytesPerSecond = 0;
      _transferStartedAt = DateTime.now();
      _lastTransferUiUpdate = null;
      _transferController = PyCleanTransferController();
    });
  }

  void _updateTransferProgress(
    int transferred,
    int total,
  ) {
    if (!mounted || !isTransferBusy) return;

    final now = DateTime.now();
    final lastUpdate = _lastTransferUiUpdate;
    final isComplete = total > 0 && transferred >= total;

    if (!isComplete &&
        lastUpdate != null &&
        now.difference(lastUpdate) < const Duration(milliseconds: 100)) {
      return;
    }

    final started = _transferStartedAt ?? now;
    final elapsedMs = now.difference(started).inMilliseconds;
    final speed = elapsedMs <= 0
        ? 0.0
        : transferred / (elapsedMs / 1000.0);

    setState(() {
      transferBytes = transferred;
      transferTotalBytes = total;
      transferBytesPerSecond = speed;
      _lastTransferUiUpdate = now;
    });
  }

  void _finishTransfer({
    required _TransferResult result,
    required String message,
  }) {
    if (!mounted) return;

    final direction = transferDirection;
    final name = transferName;

    setState(() {
      if (direction != null && name.trim().isNotEmpty) {
        transferHistory.insert(
          0,
          _TransferHistoryItem(
            direction: direction,
            result: result,
            name: name,
            bytes: transferBytes,
            totalBytes: transferTotalBytes,
            message: message,
            at: DateTime.now(),
          ),
        );

        if (transferHistory.length > 5) {
          transferHistory.removeRange(5, transferHistory.length);
        }
      }

      isTransferBusy = false;
      isTransferCancelling = false;
      transferDirection = null;
      transferName = '';
      transferBytes = 0;
      transferTotalBytes = 0;
      transferBytesPerSecond = 0;
      _transferStartedAt = null;
      _lastTransferUiUpdate = null;
      _transferController = null;
    });
  }

  void _cancelActiveTransfer() {
    if (!isTransferBusy || isTransferCancelling) return;

    setState(() {
      isTransferCancelling = true;
    });

    _transferController?.cancel();
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _transferSpeedLabel() {
    if (transferBytesPerSecond <= 0) return 'Starting...';
    return '${formatBytes(transferBytesPerSecond.round())}/s';
  }

  String _transferTimeLabel(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildTransferPanel() {
    final active = isTransferBusy && transferDirection != null;
    final progress = transferTotalBytes > 0
        ? (transferBytes / transferTotalBytes).clamp(0.0, 1.0).toDouble()
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF21222C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? const Color(0x6689B4FA)
              : const Color(0x3345475A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active
                    ? transferDirection == _TransferDirection.upload
                        ? Icons.upload_rounded
                        : Icons.download_rounded
                    : Icons.swap_vert_rounded,
                size: 18,
                color: const Color(0xFF89B4FA),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'TRANSFERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.white70,
                  ),
                ),
              ),
              if (!active && transferHistory.isNotEmpty)
                IconButton(
                  tooltip: 'Clear transfer history',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      transferHistory.clear();
                    });
                  },
                  icon: const Icon(
                    Icons.clear_all_rounded,
                    size: 18,
                    color: Colors.white38,
                  ),
                ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    transferName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  progress == null
                      ? _transferSpeedLabel()
                      : '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: Color(0xFFA6E3A1),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    transferTotalBytes > 0
                        ? '${formatBytes(transferBytes)} / ${formatBytes(transferTotalBytes)} • ${_transferSpeedLabel()}'
                        : '${formatBytes(transferBytes)} • ${_transferSpeedLabel()}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      isTransferCancelling ? null : _cancelActiveTransfer,
                  icon: isTransferCancelling
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close_rounded, size: 16),
                  label: Text(
                    isTransferCancelling ? 'Cancelling' : 'Cancel',
                  ),
                ),
              ],
            ),
          ],
          if (transferHistory.isNotEmpty) ...[
            if (active) const Divider(height: 18),
            ...transferHistory.take(3).map((entry) {
              final success = entry.result == _TransferResult.success;
              final cancelled = entry.result == _TransferResult.cancelled;
              final color = success
                  ? const Color(0xFFA6E3A1)
                  : cancelled
                      ? const Color(0xFFF9E2AF)
                      : const Color(0xFFF38BA8);
              final icon = success
                  ? Icons.check_circle_outline_rounded
                  : cancelled
                      ? Icons.cancel_outlined
                      : Icons.error_outline_rounded;

              return Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            entry.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      entry.direction == _TransferDirection.upload
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                      size: 13,
                      color: Colors.white30,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _transferTimeLabel(entry.at),
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> uploadFileToPC() async {
    if (!pcCanUpload) {
      showSnackBar(
        'Uploads are disabled in read-only mode.',
        Colors.orange,
      );
      return;
    }

    if (currentPath.isEmpty || !_api.isConfigured) {
      return;
    }

    if (isTransferBusy) {
      showSnackBar(
        'Finish or cancel the current transfer first.',
        Colors.orange,
      );
      return;
    }

    final PlatformFile? pickedFile = await FilePicker.pickFile();

    if (pickedFile == null || pickedFile.path == null) {
      return;
    }

    _beginTransfer(
      _TransferDirection.upload,
      pickedFile.name,
    );

    final controller = _transferController!;

    try {
      final result = await _api.uploadFile(
        targetDirectory: currentPath,
        filePath: pickedFile.path!,
        controller: controller,
        onProgress: _updateTransferProgress,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        final savedName = _fileNameFromPath(result.savedPath ?? '');
        final renamedForDuplicate =
            savedName.isNotEmpty && savedName != pickedFile.name;

        final message = renamedForDuplicate
            ? 'Uploaded as $savedName because that filename already existed on the PC.'
            : (result.message ?? 'Upload complete.');

        _finishTransfer(
          result: _TransferResult.success,
          message: message,
        );

        showSnackBar(
          renamedForDuplicate
              ? 'Uploaded as $savedName'
              : 'Upload complete.',
          Colors.green,
        );

        await fetchDirectory(currentPath);
      } else {
        final message = result.message ?? 'Upload failed.';

        _finishTransfer(
          result: _TransferResult.failed,
          message: message,
        );

        showSnackBar(
          message,
          Colors.red,
        );
      }
    } on PyCleanTransferCancelled {
      if (!mounted) return;

      _finishTransfer(
        result: _TransferResult.cancelled,
        message: 'Upload cancelled.',
      );

      showSnackBar(
        'Upload cancelled.',
        Colors.orange,
      );
    } catch (e) {
      debugPrint(
        'PyClean upload failed: ${pyCleanTechnicalDetails(e)}',
      );
      if (!mounted) return;

      final message = pyCleanTransferMessage(e);

      _finishTransfer(
        result: _TransferResult.failed,
        message: message,
      );

      showSnackBar(
        message,
        Colors.red,
      );
    }
  }

  Future<void> downloadFileFromPC(
    String itemPath,
    String itemName,
  ) async {
    if (!pcCanDownload) return;

    if (!_api.isConfigured || itemPath.trim().isEmpty) {
      return;
    }

    if (isTransferBusy) {
      showSnackBar(
        'Finish or cancel the current transfer first.',
        Colors.orange,
      );
      return;
    }

    _beginTransfer(
      _TransferDirection.download,
      itemName,
    );

    final controller = _transferController!;

    try {
      final result = await _api.downloadFile(
        itemPath,
        controller: controller,
        onProgress: _updateTransferProgress,
      );

      if (!mounted) return;

      if (!result.isSuccess) {
        final message =
            result.message ?? 'Download failed.';

        _finishTransfer(
          result: _TransferResult.failed,
          message: message,
        );

        showSnackBar(
          message,
          Colors.red,
        );
        return;
      }

      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save from PyClean',
        fileName: itemName,
        bytes: result.bytes,
      );

      if (!mounted) return;

      if (savedPath == null) {
        _finishTransfer(
          result: _TransferResult.cancelled,
          message: 'No save location selected.',
        );

        showSnackBar(
          'Save cancelled.',
          Colors.orange,
        );
        return;
      }

      final savedFileName = savedPath.pathSegments.isEmpty
          ? itemName
          : Uri.decodeComponent(savedPath.pathSegments.last);

      _finishTransfer(
        result: _TransferResult.success,
        message: 'Saved as $savedFileName',
      );

      showSnackBar(
        'Saved to device.',
        Colors.green,
      );
    } on PyCleanTransferCancelled {
      if (!mounted) return;

      _finishTransfer(
        result: _TransferResult.cancelled,
        message: 'Download cancelled.',
      );

      showSnackBar(
        'Download cancelled.',
        Colors.orange,
      );
    } catch (e) {
      debugPrint(
        'PyClean download failed: ${pyCleanTechnicalDetails(e)}',
      );
      if (!mounted) return;

      final message = pyCleanTransferMessage(e);

      _finishTransfer(
        result: _TransferResult.failed,
        message: message,
      );

      showSnackBar(
        message,
        Colors.red,
      );
    }
  }

  Future<void> renameRemoteItem(
    String itemPath,
    String itemName,
  ) async {
    if (!pcCanRename) return;

    String draftName = itemName;

    final String? newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextFormField(
          initialValue: itemName,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New name',
            hintText: 'Enter a new name',
          ),
          onChanged: (value) {
            draftName = value;
          },
          onFieldSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) {
              Navigator.pop(ctx, trimmed);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = draftName.trim();
              if (trimmed.isNotEmpty) {
                Navigator.pop(ctx, trimmed);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (!mounted || newName == null || newName.trim().isEmpty) {
      return;
    }

    if (newName.trim() == itemName) {
      return;
    }

    try {
      final result = await _api.renameItem(
        itemPath: itemPath,
        newName: newName.trim(),
      );

      if (!mounted) return;

      if (result.isSuccess) {
        showSnackBar(
          result.message ?? 'Renamed.',
          Colors.green,
        );
        await fetchDirectory(currentPath);
      } else {
        showSnackBar(
          result.message ?? 'Rename failed.',
          Colors.red,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showSnackBar(
        'Error rename: $e',
        Colors.red,
      );
    }
  }

  Future<void> moveRemoteItem(
    String itemPath,
    bool isDirectory,
  ) async {
    if (!pcCanMove) return;

    final String? targetDirectory = await showDialog<String>(
      context: context,
      builder: (_) => RemoteFolderPickerDialog(
        api: _api,
        initialPath: currentPath,
        blockedPath: isDirectory ? itemPath : null,
      ),
    );

    if (!mounted || targetDirectory == null || targetDirectory.trim().isEmpty) {
      return;
    }

    try {
      final result = await _api.moveItem(
        itemPath: itemPath,
        targetDirectory: targetDirectory,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        showSnackBar(
          result.message ?? 'Moved.',
          Colors.green,
        );
        await fetchDirectory(currentPath);
      } else {
        showSnackBar(
          result.message ?? 'Move failed.',
          Colors.red,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showSnackBar(
        'Error move: $e',
        Colors.red,
      );
    }
  }


  Future executeSortFolder(
    String targetPath,
  ) async {
    if (!pcCanSort) return;

    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(
              "Organize this folder?",
            ),
            content: Text(
              "Files in this folder will be grouped "
              "into subfolders based on "
              "file type.\n\nPath: $targetPath",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx, false);
                },
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFFA6E3A1),
                ),
                onPressed: () {
                  Navigator.pop(ctx, true);
                },
                child: const Text(
                  "Organize",
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      showSnackBar(
        "Organizing folder...",
        Colors.blue,
      );

      final result = await _api.sortFolder(targetPath);

      if (result.isSuccess) {
        showSnackBar(
          result.message ??
              "Folder organized.",
          Colors.green,
        );

        fetchDirectory(currentPath);
      } else {
        showSnackBar(
          result.message ??
              "Organize failed.",
          Colors.red,
        );
      }
    } catch (e) {
      showSnackBar(
        "Error: $e",
        Colors.red,
      );
    }
  }

  Future deleteItem(
    String itemPath,
    String itemName,
  ) async {
    if (!pcCanDelete) return;

    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(
              "Delete item?",
            ),
            content: Text(
              "Permanently delete "
              "'$itemName' from the PC?",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx, false);
                },
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.redAccent,
                ),
                onPressed: () {
                  Navigator.pop(ctx, true);
                },
                child: const Text(
                  "Delete",
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      final result = await _api.deleteItem(itemPath);

      if (result.isSuccess) {
        showSnackBar(
          result.message ??
              "Deleted.",
          Colors.green,
        );

        fetchDirectory(currentPath);
      } else {
        showSnackBar(
          result.message ??
              "Delete failed.",
          Colors.red,
        );
      }
    } catch (e) {
      showSnackBar(
        "Error: $e",
        Colors.red,
      );
    }
  }

  void show3dItemModal(Map item) {
    final bool isDir =
        item['is_dir'] ?? false;

    final String name =
        item['name'] ?? 'Unknown';

    final String path =
        item['path'] ?? '-';

    final String formattedSize =
        isDir
            ? 'Folder'
            : formatBytes(item['size']);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: InkWell(
          onTap: () {
            Navigator.pop(ctx);
          },
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ArHologramWidget(
                isDir: isDir,
              ),

              const SizedBox(
                height: 20,
              ),

              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color:
                      const Color(0xEE1E1E2E),
                  borderRadius:
                      BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFF9E2AF)
                        .withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFFF9E2AF)
                              .withValues(
                            alpha: 0.15,
                          ),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      name,
                      textAlign:
                          TextAlign.center,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          const TextStyle(
                        fontSize: 16,
                        fontWeight:
                            FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    Wrap(
                      alignment:
                          WrapAlignment.center,
                      crossAxisAlignment:
                          WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration:
                              BoxDecoration(
                            color: isDir
                                ? const Color(
                                    0x3389B4FA,
                                  )
                                : const Color(
                                    0x33A6E3A1,
                                  ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              12,
                            ),
                          ),
                          child: Text(
                            isDir
                                ? "Folder"
                                : "File",
                            style: TextStyle(
                              color: isDir
                                  ? const Color(
                                      0xFF89B4FA,
                                    )
                                  : const Color(
                                      0xFFA6E3A1,
                                    ),
                              fontSize: 12,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),

                        if (!isDir)
                          Text(
                            formattedSize,
                            style:
                                const TextStyle(
                              color:
                                  Color(0xFFF9E2AF),
                              fontSize: 13,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Text(
                      path,
                      textAlign:
                          TextAlign.center,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                        fontFamily:
                            'monospace',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 15,
              ),

              const Text(
                "Tap anywhere to close",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showSnackBar(
    String msg,
    Color color,
  ) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration:
            const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: !isConnected
            ? buildConnectScreen()
            : buildExplorerScreen(),
      ),

      floatingActionButton: !isSelectionMode
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: "deviceHubBtn",
                  tooltip: "Device Hub",
                  onPressed: openDeviceHub,
                  backgroundColor: const Color(0xFF2A2A3C),
                  foregroundColor: const Color(0xFFCBA6F7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(
                      color: Color(0xFFCBA6F7),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.devices_other,
                    size: 20,
                  ),
                ),

                if (isConnected) ...[
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: "qrScanBtn",
                    tooltip: "Scan another PC",
                    onPressed: openScanner,
                    backgroundColor: const Color(0xFF2A2A3C),
                    foregroundColor: const Color(0xFF89B4FA),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(
                        color: Color(0xFF89B4FA),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner,
                      size: 20,
                    ),
                  ),

                  if (pcCanUpload) ...[
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                    heroTag: "uploadBtn",
                    onPressed: isTransferBusy ? null : uploadFileToPC,
                    backgroundColor: const Color(0xFF89B4FA),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.upload_file,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                  ],
                ],
              ],
            )
          : null,
    );
  }

  Widget buildConnectScreen() {
    final hasSavedPc = savedServerUrl.trim().isNotEmpty;
    final connectionBusy =
        isCheckingSavedPc || isConnectingToPc || isReconnectingToPc;
    final statusColor =
        isConnectingToPc || isReconnectingToPc || isCheckingSavedPc
            ? const Color(0xFFF9E2AF)
            : savedPcOnline == true
                ? const Color(0xFFA6E3A1)
                : savedPcOnline == false
                    ? Colors.redAccent
                    : Colors.grey;
    final statusText = isConnectingToPc
        ? 'CONNECTING'
        : isReconnectingToPc
            ? 'RECONNECTING'
            : isCheckingSavedPc
                ? 'CHECKING'
                : savedPcOnline == true
                    ? 'ONLINE'
                    : savedPcOnline == false
                        ? 'OFFLINE'
                        : 'UNKNOWN';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.phonelink_setup,
              size: 80,
              color: Color(0xFF89B4FA),
            ),
            const SizedBox(height: 20),
            const Text(
              'PC Remote',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect to a PyClean PC',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            if (hasSavedPc) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF21222C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.55),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            savedDeviceName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      savedServerUrl,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    if (savedPcConnectionHint != null &&
                        savedPcConnectionHint!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 17,
                              color: Colors.orangeAccent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                savedPcConnectionHint!,
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
                    ],
                    if (savedLastPath.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Last folder: $savedLastPath',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: connectionBusy
                                ? null
                                : reconnectSavedPc,
                            icon: isReconnectingToPc
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.link),
                            label: Text(
                              isReconnectingToPc
                                  ? 'Reconnecting...'
                                  : 'Reconnect',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Check status',
                          onPressed: connectionBusy
                              ? null
                              : refreshSavedPcStatus,
                          icon: isCheckingSavedPc
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                backgroundColor: const Color(0xFF89B4FA),
              ),
              icon: isConnectingToPc
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(
                      Icons.qr_code_scanner,
                      color: Colors.black,
                    ),
              label: Text(
                isConnectingToPc
                    ? 'Connecting...'
                    : hasSavedPc
                        ? 'Scan another PC'
                        : 'Scan PC',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: connectionBusy ? null : openScanner,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildExplorerScreen() {
    return Column(
      children: [
        if (isSelectionMode)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 7,
            ),
            color: const Color(0xFF2A2A3C),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Cancel selection',
                  onPressed: isBatchBusy ? null : clearSelection,
                  icon: const Icon(Icons.close),
                ),
                Expanded(
                  child: Text(
                    '${selectedPaths.length} selected',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isBatchBusy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  IconButton(
                    tooltip: 'Select all',
                    onPressed: filteredFileItems.isEmpty
                        ? null
                        : selectAllVisible,
                    icon: const Icon(Icons.select_all),
                  ),
                  if (pcCanMove)
                    IconButton(
                      tooltip: 'Move selected',
                      onPressed: selectedPaths.isEmpty
                          ? null
                          : moveSelectedItems,
                      icon: const Icon(
                        Icons.drive_file_move_outline,
                        color: Color(0xFFCBA6F7),
                      ),
                    ),
                  if (pcCanDelete)
                    IconButton(
                      tooltip: 'Delete selected',
                      onPressed: selectedPaths.isEmpty
                          ? null
                          : deleteSelectedItems,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                    ),
                ],
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            color: const Color(0xFF2A2A3C),
            child: Row(
              children: [
                if (currentPath != parentPath)
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => fetchDirectory(parentPath),
                    tooltip: 'Up one folder',
                  ),
                if (currentPath != parentPath)
                  const SizedBox(width: 8),
                const Icon(
                  Icons.folder_special,
                  color: Color(0xFFA6E3A1),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _displayCurrentPath,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFA6E3A1),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (pcShareEnabled || pcReadOnly) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: pcReadOnly
                          ? const Color(0x22F9E2AF)
                          : const Color(0x2289B4FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: pcReadOnly
                            ? const Color(0x66F9E2AF)
                            : const Color(0x6689B4FA),
                      ),
                    ),
                    child: Text(
                      _accessLabel,
                      style: TextStyle(
                        color: pcReadOnly
                            ? const Color(0xFFF9E2AF)
                            : const Color(0xFF89B4FA),
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x2239D98A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0x6639D98A),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 7,
                        color: Color(0xFFA6E3A1),
                      ),
                      SizedBox(width: 5),
                      Text(
                        'ONLINE',
                        style: TextStyle(
                          color: Color(0xFFA6E3A1),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (_canSelectItems)
                  IconButton(
                    tooltip: 'Select items',
                    onPressed: filteredFileItems.isEmpty
                        ? null
                        : enterSelectionMode,
                    icon: const Icon(
                      Icons.checklist,
                      size: 20,
                      color: Color(0xFF89B4FA),
                    ),
                  ),
                if (pcCanSort)
                  OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFFA6E3A1),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(
                    Icons.cleaning_services,
                    color: Color(0xFFA6E3A1),
                    size: 14,
                  ),
                  label: const Text(
                    'Organize',
                    style: TextStyle(
                      color: Color(0xFFA6E3A1),
                      fontSize: 11,
                    ),
                  ),
                  onPressed: () => executeSortFolder(currentPath),
                ),
                if (pcCanSort)
                  const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => fetchDirectory(currentPath),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),

        if (isTransferBusy || transferHistory.isNotEmpty)
          _buildTransferPanel(),

        Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          child: TextField(
            controller:
                searchController,
            onChanged:
                filterSearch,

            decoration:
                InputDecoration(
              hintText:
                  "Search this folder...",

              prefixIcon:
                  const Icon(
                Icons.search,
                color:
                    Color(0xFF89B4FA),
              ),

              suffixIcon:
                  searchController
                          .text
                          .isNotEmpty
                      ? IconButton(
                          icon:
                              const Icon(
                            Icons.clear,
                          ),
                          onPressed: () {
                            searchController
                                .clear();

                            filterSearch(
                              '',
                            );
                          },
                        )
                      : null,

              filled: true,

              fillColor:
                  const Color(
                0xFF21222C,
              ),

              contentPadding:
                  const EdgeInsets
                      .symmetric(
                vertical: 8,
              ),

              border:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius
                        .circular(
                  12,
                ),
                borderSide:
                    BorderSide.none,
              ),
            ),
          ),
        ),

        Expanded(
          child: isLoadingFiles
              ? const Center(
                  child:
                      CircularProgressIndicator(),
                )
              : filteredFileItems
                      .isEmpty
                  ? const Center(
                      child: Text(
                        "No files found",
                      ),
                    )
                  : ListView.builder(
                      itemCount:
                          filteredFileItems
                              .length,

                      itemBuilder:
                          (context, index) {
                        final item =
                            filteredFileItems[
                                index];

                        final bool isDir =
                            item['is_dir'] ??
                                false;

                        final String name =
                            item['name'] ??
                                '';

                        final String path =
                            item['path'] ??
                                '';

                        final bool isSelected =
                            selectedPaths.contains(path);

                        return Card(
                          margin:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          color: isSelected
                              ? const Color(0xFF30354A)
                              : const Color(0xFF21222C),

                          child: ListTile(
                            dense: true,

                            leading: Icon(
                              isDir
                                  ? Icons.folder
                                  : Icons
                                      .insert_drive_file,
                              color: isDir
                                  ? const Color(
                                      0xFF89B4FA,
                                    )
                                  : Colors.grey,
                            ),

                            title: Text(
                              name,
                              style:
                                  const TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    FontWeight
                                        .w500,
                              ),
                            ),

                            subtitle: Text(
                              isDir
                                  ? "Folder"
                                  : formatBytes(
                                      item['size'],
                                    ),
                              style: TextStyle(
                                fontSize: 10,
                                color: isDir
                                    ? Colors.grey
                                    : const Color(
                                        0xFFA6E3A1,
                                      ),
                              ),
                            ),

                            onTap: () {
                              if (isSelectionMode) {
                                toggleSelection(item);
                              } else if (isDir) {
                                fetchDirectory(path);
                              }
                            },

                            onLongPress: () {
                              if (isSelectionMode) {
                                toggleSelection(item);
                              } else if (_canSelectItems) {
                                enterSelectionMode(item);
                              }
                            },

                            trailing: isSelectionMode
                                ? Checkbox(
                                    value: isSelected,
                                    onChanged: isBatchBusy
                                        ? null
                                        : (_) => toggleSelection(item),
                                  )
                                : PopupMenuButton(
                              icon:
                                  const Icon(
                                Icons.more_vert,
                                color:
                                    Colors.white70,
                                size: 18,
                              ),

                              onSelected:
                                  (value) {
                                if (value ==
                                    'inspect') {
                                  show3dItemModal(
                                    item,
                                  );
                                } else if (value ==
                                    'download') {
                                  downloadFileFromPC(
                                    path,
                                    name,
                                  );
                                } else if (value ==
                                    'rename') {
                                  renameRemoteItem(
                                    path,
                                    name,
                                  );
                                } else if (value ==
                                    'move') {
                                  moveRemoteItem(
                                    path,
                                    isDir,
                                  );
                                } else if (value ==
                                    'delete') {
                                  deleteItem(
                                    path,
                                    name,
                                  );
                                }
                              },

                              itemBuilder:
                                  (BuildContext
                                      context) =>
                                      [
                                const PopupMenuItem(
                                  value:
                                      'inspect',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons
                                            .view_in_ar,
                                        color:
                                            Color(
                                          0xFF89B4FA,
                                        ),
                                        size: 18,
                                      ),
                                      SizedBox(
                                        width: 10,
                                      ),
                                      Text(
                                        "3D preview",
                                      ),
                                    ],
                                  ),
                                ),

                                if (!isDir && pcCanDownload)
                                  const PopupMenuItem(
                                    value:
                                        'download',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.download_outlined,
                                          color: Color(0xFFA6E3A1),
                                          size: 18,
                                        ),
                                        SizedBox(
                                          width: 10,
                                        ),
                                        Text(
                                          'Download',
                                          style: TextStyle(
                                            color: Color(0xFFA6E3A1),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                if (pcCanRename)
                                  const PopupMenuItem(
                                  value:
                                      'rename',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.edit_outlined,
                                        color:
                                            Color(
                                          0xFFF9E2AF,
                                        ),
                                        size: 18,
                                      ),
                                      SizedBox(
                                        width: 10,
                                      ),
                                      Text(
                                        'Rename',
                                      ),
                                    ],
                                  ),
                                ),

                                if (pcCanMove)
                                  const PopupMenuItem(
                                  value:
                                      'move',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.drive_file_move_outline,
                                        color:
                                            Color(
                                          0xFFCBA6F7,
                                        ),
                                        size: 18,
                                      ),
                                      SizedBox(
                                        width: 10,
                                      ),
                                      Text(
                                        'Move',
                                      ),
                                    ],
                                  ),
                                ),

                                if (pcCanDelete)
                                  const PopupMenuItem(
                                  value:
                                      'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons
                                            .delete_outline,
                                        color:
                                            Colors
                                                .redAccent,
                                        size: 18,
                                      ),
                                      SizedBox(
                                        width: 10,
                                      ),
                                      Text(
                                        "Delete",
                                        style:
                                            TextStyle(
                                          color:
                                              Colors
                                                  .redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> openDeviceHub() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DeviceHubScreen(),
      ),
    );
  }

  Future<void> openScanner() async {
    final result =
        await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const QrScannerPage(),
      ),
    );

    if (!mounted ||
        result == null ||
        result.trim().isEmpty) {
      return;
    }

    await connectToServer(
      result.trim(),
    );
  }
}

enum _TransferDirection {
  upload,
  download,
}

enum _TransferResult {
  success,
  failed,
  cancelled,
}

class _TransferHistoryItem {
  const _TransferHistoryItem({
    required this.direction,
    required this.result,
    required this.name,
    required this.bytes,
    required this.totalBytes,
    required this.message,
    required this.at,
  });

  final _TransferDirection direction;
  final _TransferResult result;
  final String name;
  final int bytes;
  final int totalBytes;
  final String message;
  final DateTime at;
}


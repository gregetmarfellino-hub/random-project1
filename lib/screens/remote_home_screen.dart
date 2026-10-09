import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/connection_store.dart';
import '../services/pyclean_api.dart';
import '../widgets/ar_hologram_widget.dart';
import '../widgets/remote_folder_picker.dart';
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
  bool? savedPcOnline;

  String savedServerUrl = '';
  String savedDeviceName = 'PyClean PC';
  String savedLastPath = '';

  String currentPath = "";
  String parentPath = "";

  List allFileItems = [];
  List filteredFileItems = [];

  bool isLoadingFiles = false;

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
    searchController.dispose();
    super.dispose();
  }

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
    });

    _api.setServerUrl(savedServerUrl);

    try {
      final status = await _api.status();
      if (!mounted) return;

      setState(() {
        savedPcOnline = status.isSuccess;
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        savedPcOnline = false;
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
  }) async {
    _api.setServerUrl(url);

    try {
      final status = await _api.status();

      if (!status.isSuccess) {
        throw StateError('PyClean server tidak tersedia');
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
      });

      final targetPath = preferredPath?.trim();
      await fetchDirectory(
        targetPath == null || targetPath.isEmpty ? null : targetPath,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isConnected = false;
        savedPcOnline = false;
      });

      showSnackBar(
        'Tidak bisa terhubung ke PC: $e',
        Colors.red,
      );
    }
  }

  Future<void> reconnectSavedPc() async {
    if (savedServerUrl.trim().isEmpty) return;

    await connectToServer(
      savedServerUrl,
      preferredPath: savedLastPath,
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
          "Gagal mengambil direktori PC",
          Colors.red,
        );

        setState(() {
          isLoadingFiles = false;
        });
      }
    } catch (e) {
      showSnackBar(
        "Koneksi Error: $e",
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
    if (isBatchBusy) return;

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
          ? '✅ $moved item berhasil dipindahkan.'
          : '$moved berhasil dipindahkan, $failed gagal.',
      failed == 0 ? Colors.green : Colors.orange,
    );
  }

  Future<void> deleteSelectedItems() async {
    final items = selectedItems;
    if (items.isEmpty || isBatchBusy) return;

    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hapus beberapa item?'),
            content: Text(
              '${items.length} item akan dihapus dari PC secara permanen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hapus semua'),
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
          ? '✅ $deleted item berhasil dihapus.'
          : '$deleted berhasil dihapus, $failed gagal.',
      failed == 0 ? Colors.green : Colors.orange,
    );
  }

  Future<void> uploadFileToPC() async {
    if (currentPath.isEmpty || !_api.isConfigured) {
      return;
    }

    final PlatformFile? pickedFile =
        await FilePicker.pickFile();

    if (pickedFile == null || pickedFile.path == null) {
      return;
    }

    showSnackBar(
      "Mengunggah file ke PC... ⏳",
      Colors.blue,
    );

    try {
      final result = await _api.uploadFile(
        targetDirectory: currentPath,
        filePath: pickedFile.path!,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        showSnackBar(
          "✅ File berhasil terkirim ke PC!",
          Colors.green,
        );

        await fetchDirectory(currentPath);
      } else {
        showSnackBar(
          "Gagal upload: ${result.rawBody}",
          Colors.red,
        );
      }
    } catch (e) {
      if (!mounted) return;

      showSnackBar(
        "Error upload: $e",
        Colors.red,
      );
    }
  }

  Future<void> downloadFileFromPC(
    String itemPath,
    String itemName,
  ) async {
    if (!_api.isConfigured || itemPath.trim().isEmpty) {
      return;
    }

    showSnackBar(
      'Mengunduh $itemName dari PC... ⏳',
      Colors.blue,
    );

    try {
      final result = await _api.downloadFile(itemPath);

      if (!mounted) return;

      if (!result.isSuccess) {
        showSnackBar(
          result.message ?? 'Gagal mengunduh file dari PC',
          Colors.red,
        );
        return;
      }

      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Simpan file dari PyClean PC',
        fileName: itemName,
        bytes: result.bytes,
      );

      if (!mounted) return;

      if (savedPath == null) {
        showSnackBar(
          'Penyimpanan dibatalkan',
          Colors.orange,
        );
        return;
      }

      showSnackBar(
        '✅ $itemName berhasil disimpan ke HP!',
        Colors.green,
      );
    } catch (e) {
      if (!mounted) return;

      showSnackBar(
        'Error download: $e',
        Colors.red,
      );
    }
  }

  Future<void> renameRemoteItem(
    String itemPath,
    String itemName,
  ) async {
    String draftName = itemName;

    final String? newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ganti Nama'),
        content: TextFormField(
          initialValue: itemName,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama baru',
            hintText: 'Masukkan nama file/folder',
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
            child: const Text('Batal'),
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
          result.message ?? 'Nama berhasil diubah.',
          Colors.green,
        );
        await fetchDirectory(currentPath);
      } else {
        showSnackBar(
          result.message ?? 'Gagal mengganti nama.',
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
          result.message ?? 'Item berhasil dipindahkan.',
          Colors.green,
        );
        await fetchDirectory(currentPath);
      } else {
        showSnackBar(
          result.message ?? 'Gagal memindahkan item.',
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
    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(
              "🧹 Rapikan Folder ini?",
            ),
            content: Text(
              "File di folder ini akan dikelompokkan "
              "otomatis ke sub-folder khusus berdasarkan "
              "jenis filenya.\n\nPath: $targetPath",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx, false);
                },
                child: const Text("Batal"),
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
                  "Ya, Sortir!",
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
        "Mulai merapikan folder...",
        Colors.blue,
      );

      final result = await _api.sortFolder(targetPath);

      if (result.isSuccess) {
        showSnackBar(
          result.message ??
              "Sukses menyortir!",
          Colors.green,
        );

        fetchDirectory(currentPath);
      } else {
        showSnackBar(
          result.message ??
              "Gagal menyortir",
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
    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(
              "Konfirmasi Hapus",
            ),
            content: Text(
              "Yakin ingin menghapus "
              "'$itemName' dari PC secara permanen?",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx, false);
                },
                child: const Text("Batal"),
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
                  "Ya, Hapus",
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
              "Item terhapus!",
          Colors.green,
        );

        fetchDirectory(currentPath);
      } else {
        showSnackBar(
          result.message ??
              "Gagal menghapus",
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
            ? 'Folder / Directory'
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
                                ? "📁 Directory"
                                : "📄 File",
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
                "( Ketuk layar untuk menutup )",
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

      floatingActionButton:
          isConnected && !isSelectionMode
              ? Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.small(
                      heroTag:
                          "qrScanBtn",
                      tooltip:
                          "Scan QR PC Lain",
                      onPressed:
                          openScanner,
                      backgroundColor:
                          const Color(
                        0xFF2A2A3C,
                      ),
                      foregroundColor:
                          const Color(
                        0xFF89B4FA,
                      ),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                          12,
                        ),
                        side:
                            const BorderSide(
                          color:
                              Color(0xFF89B4FA),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        size: 20,
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                      FloatingActionButton.small(
                     heroTag: "uploadBtn",
                        onPressed: uploadFileToPC,
                      backgroundColor: const Color(0xFF89B4FA),
                        shape: RoundedRectangleBorder(
                       borderRadius: BorderRadius.circular(12),
                         ),
                       child: const Icon(Icons.upload_file, color: Colors.black, size: 20
                      ),
                    ),
                  ],
                )
              : null,
    );
  }

  Widget buildConnectScreen() {
    final hasSavedPc = savedServerUrl.trim().isNotEmpty;
    final statusColor = savedPcOnline == true
        ? const Color(0xFFA6E3A1)
        : savedPcOnline == false
            ? Colors.redAccent
            : Colors.grey;
    final statusText = isCheckingSavedPc
        ? 'Checking...'
        : savedPcOnline == true
            ? 'Online'
            : savedPcOnline == false
                ? 'Offline'
                : 'Unknown';

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
              'PyClean PC Remote',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hubungkan ke PC kamu',
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
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
                            onPressed: isCheckingSavedPc
                                ? null
                                : reconnectSavedPc,
                            icon: const Icon(Icons.link),
                            label: const Text('Reconnect'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Check status',
                          onPressed: isCheckingSavedPc
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
              icon: const Icon(
                Icons.qr_code_scanner,
                color: Colors.black,
              ),
              label: Text(
                hasSavedPc ? 'Scan QR PC Lain' : 'Scan QR Code PC',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: openScanner,
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
                  tooltip: 'Batal pilih',
                  onPressed: isBatchBusy ? null : clearSelection,
                  icon: const Icon(Icons.close),
                ),
                Expanded(
                  child: Text(
                    '${selectedPaths.length} dipilih',
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
                    tooltip: 'Pilih semua yang terlihat',
                    onPressed: filteredFileItems.isEmpty
                        ? null
                        : selectAllVisible,
                    icon: const Icon(Icons.select_all),
                  ),
                  IconButton(
                    tooltip: 'Pindahkan yang dipilih',
                    onPressed: selectedPaths.isEmpty
                        ? null
                        : moveSelectedItems,
                    icon: const Icon(
                      Icons.drive_file_move_outline,
                      color: Color(0xFFCBA6F7),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hapus yang dipilih',
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
                    tooltip: 'Kembali ke folder atas',
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
                    currentPath,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFA6E3A1),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                IconButton(
                  tooltip: 'Pilih beberapa item',
                  onPressed: filteredFileItems.isEmpty
                      ? null
                      : enterSelectionMode,
                  icon: const Icon(
                    Icons.checklist,
                    size: 20,
                    color: Color(0xFF89B4FA),
                  ),
                ),
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
                    'Sortir',
                    style: TextStyle(
                      color: Color(0xFFA6E3A1),
                      fontSize: 11,
                    ),
                  ),
                  onPressed: () => executeSortFolder(currentPath),
                ),
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
                  "Cari file di folder ini...",

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
                        "Kosong atau file tidak ditemukan",
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
                              } else {
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
                                        "Inspeksi 3D",
                                      ),
                                    ],
                                  ),
                                ),

                                if (!isDir)
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
                                          'Download ke HP',
                                          style: TextStyle(
                                            color: Color(0xFFA6E3A1),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

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
                                        'Ganti Nama',
                                      ),
                                    ],
                                  ),
                                ),

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
                                        'Pindahkan',
                                      ),
                                    ],
                                  ),
                                ),

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
                                        "Hapus File",
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

import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/pyclean_api.dart';
import '../widgets/ar_hologram_widget.dart';
import 'qr_scanner_page.dart';

class RemoteHomeScreen extends StatefulWidget {
  const RemoteHomeScreen({super.key});

  @override
  State<RemoteHomeScreen> createState() => _RemoteHomeScreenState();
}

class _RemoteHomeScreenState extends State<RemoteHomeScreen> {
  final PyCleanApi _api = PyCleanApi();

  bool isConnected = false;

  String currentPath = "";
  String parentPath = "";

  List allFileItems = [];
  List filteredFileItems = [];

  bool isLoadingFiles = false;

  final TextEditingController searchController = TextEditingController();

  void connectToServer(String url) {
    _api.setServerUrl(url);

    setState(() {
      isConnected = true;
    });

    fetchDirectory(null);
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
        });
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
          isConnected
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
    return Center(
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.phonelink_setup,
            size: 80,
            color: Color(0xFF89B4FA),
          ),

          const SizedBox(
            height: 20,
          ),

          const Text(
            "PyClean PC Remote",
            style: TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          const Text(
            "Hubungkan ke PC kamu",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),

          const SizedBox(
            height: 30,
          ),

          ElevatedButton.icon(
            style:
                ElevatedButton.styleFrom(
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              backgroundColor:
                  const Color(
                0xFF89B4FA,
              ),
            ),
            icon: const Icon(
              Icons.qr_code_scanner,
              color: Colors.black,
            ),
            label: const Text(
              "Scan QR Code PC",
              style: TextStyle(
                color: Colors.black,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            onPressed:
                openScanner,
          ),
        ],
      ),
    );
  }

  Widget buildExplorerScreen() {
    return Column(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          color:
              const Color(0xFF2A2A3C),

          child: Row(
            children: [
              if (currentPath != parentPath)
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    size: 20,
                  ),
                  padding:
                      EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(),
                  onPressed: () =>
                      fetchDirectory(
                    parentPath,
                  ),
                  tooltip:
                      "Kembali ke folder atas",
                ),

              if (currentPath != parentPath)
                const SizedBox(
                  width: 8,
                ),

              const Icon(
                Icons.folder_special,
                color:
                    Color(0xFFA6E3A1),
                size: 18,
              ),

              const SizedBox(
                width: 8,
              ),

              Expanded(
                child: Text(
                  currentPath,
                  style:
                      const TextStyle(
                    fontFamily:
                        'monospace',
                    fontSize: 12,
                    color:
                        Color(0xFFA6E3A1),
                  ),
                  overflow:
                      TextOverflow.ellipsis,
                ),
              ),

              OutlinedButton.icon(
                style:
                    OutlinedButton.styleFrom(
                  side:
                      const BorderSide(
                    color:
                        Color(0xFFA6E3A1),
                  ),
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize:
                      Size.zero,
                  tapTargetSize:
                      MaterialTapTargetSize
                          .shrinkWrap,
                ),
                icon: const Icon(
                  Icons.cleaning_services,
                  color:
                      Color(0xFFA6E3A1),
                  size: 14,
                ),
                label: const Text(
                  "Sortir",
                  style: TextStyle(
                    color:
                        Color(0xFFA6E3A1),
                    fontSize: 11,
                  ),
                ),
                onPressed: () =>
                    executeSortFolder(
                  currentPath,
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              IconButton(
                icon: const Icon(
                  Icons.refresh,
                  size: 20,
                ),
                padding:
                    EdgeInsets.zero,
                constraints:
                    const BoxConstraints(),
                onPressed: () =>
                    fetchDirectory(
                  currentPath,
                ),
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

                        return Card(
                          margin:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          color:
                              const Color(
                            0xFF21222C,
                          ),

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
                              if (isDir) {
                                fetchDirectory(
                                  path,
                                );
                              }
                            },

                            onLongPress: () =>
                                show3dItemModal(
                              item,
                            ),

                            trailing:
                                PopupMenuButton(
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

    connectToServer(
      result.trim(),
    );
  }
}

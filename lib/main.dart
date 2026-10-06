import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const PyCleanRemoteApp());
}

class PyCleanRemoteApp extends StatelessWidget {
  const PyCleanRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PyClean Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E2E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF89B4FA),
          surface: Color(0xFF2A2A3C),
        ),
      ),
      home: const RemoteHomeScreen(),
    );
  }
}

class RemoteHomeScreen extends StatefulWidget {
  const RemoteHomeScreen({super.key});

  @override
  State<RemoteHomeScreen> createState() => _RemoteHomeScreenState();
}

class _RemoteHomeScreenState extends State<RemoteHomeScreen> {
  String serverUrl = "";
  bool isConnected = false;

  String currentPath = "";
  String parentPath = "";

  List allFileItems = [];
  List filteredFileItems = [];

  bool isLoadingFiles = false;

  final TextEditingController searchController = TextEditingController();

  void connectToServer(String url) {
    setState(() {
      serverUrl = url.trim();

      if (serverUrl.endsWith('/')) {
        serverUrl = serverUrl.substring(0, serverUrl.length - 1);
      }

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
    if (serverUrl.isEmpty) return;

    setState(() {
      isLoadingFiles = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$serverUrl/api/browse'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'path': path,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          currentPath = data['current_path'] ?? '';
          parentPath = data['parent_path'] ?? '';

          allFileItems = data['items'] ?? [];
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
    if (currentPath.isEmpty || serverUrl.isEmpty) {
      return;
    }

    final PlatformFile? pickedFile =
        await FilePicker.pickFile();

    if (pickedFile == null || pickedFile.path == null) {
      return;
    }

    final File fileToUpload =
        File(pickedFile.path!);

    showSnackBar(
      "Mengunggah file ke PC... ⏳",
      Colors.blue,
    );

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/api/upload'),
      );

      request.fields['target_dir'] = currentPath;

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          fileToUpload.path,
        ),
      );

      final streamedResponse =
          await request.send();

      final response =
          await http.Response.fromStream(
        streamedResponse,
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        showSnackBar(
          "✅ File berhasil terkirim ke PC!",
          Colors.green,
        );

        await fetchDirectory(currentPath);
      } else {
        showSnackBar(
          "Gagal upload: ${response.body}",
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

      final response = await http.post(
        Uri.parse(
          '$serverUrl/api/execute-sort',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'target_dir': targetPath,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        showSnackBar(
          data['message'] ??
              "Sukses menyortir!",
          Colors.green,
        );

        fetchDirectory(currentPath);
      } else {
        showSnackBar(
          data['message'] ??
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
      final response = await http.post(
        Uri.parse(
          '$serverUrl/api/delete',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'path': itemPath,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        showSnackBar(
          data['message'] ??
              "Item terhapus!",
          Colors.green,
        );

        fetchDirectory(currentPath);
      } else {
        showSnackBar(
          data['message'] ??
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

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() =>
      _QrScannerPageState();
}

class _QrScannerPageState
    extends State<QrScannerPage> {
  late final MobileScannerController
      _controller;

  bool _didReturnResult = false;

  @override
  void initState() {
    super.initState();

    _controller =
        MobileScannerController(
      facing:
          CameraFacing.back,
      detectionSpeed:
          DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetection(
    BarcodeCapture capture,
  ) {
    if (_didReturnResult) return;

    for (final barcode
        in capture.barcodes) {
      final value =
          barcode.rawValue?.trim();

      if (value != null &&
          value.isNotEmpty) {
        _didReturnResult = true;

        Navigator.of(context)
            .pop(value);

        return;
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          Colors.black,

      appBar: AppBar(
        title: const Text(
          "Scan QR Code PC",
        ),

        backgroundColor:
            Colors.black,

        foregroundColor:
            Colors.white,

        actions: [
          IconButton(
            tooltip: "Flash",

            icon: const Icon(
              Icons.flash_on,
            ),

            onPressed: () {
              _controller
                  .toggleTorch();
            },
          ),

          IconButton(
            tooltip:
                "Ganti kamera",

            icon: const Icon(
              Icons.flip_camera_android,
            ),

            onPressed: () {
              _controller
                  .switchCamera();
            },
          ),
        ],
      ),

      body: Stack(
        fit: StackFit.expand,

        children: [
          MobileScanner(
            controller:
                _controller,

            onDetect:
                _handleDetection,

           errorBuilder: (context, error) {
              return Container(
                color:
                    Colors.black,

                alignment:
                    Alignment.center,

                padding:
                    const EdgeInsets
                        .all(24),

                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,

                  children: [
                    const Icon(
                      Icons
                          .camera_alt_outlined,
                      color:
                          Colors.redAccent,
                      size: 64,
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    const Text(
                      "Kamera tidak bisa dibuka",
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            Colors.white,
                        fontSize: 20,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    Text(
                    'CODE: ${error.errorCode}\n\n'
                    'MESSAGE: ${error.errorDetails?.message ?? 'No message'}\n\n'
                    'CODE: ${error.errorDetails?.code ?? 'No native code'}\n\n'
                    'DETAILS: ${error.errorDetails?.details ?? 'No details'}',
                     textAlign: TextAlign.center,
                     style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                       ),
                     ),

                    const SizedBox(
                      height: 20,
                    ),

                    FilledButton.icon(
                      onPressed: () {
                        openAppSettings();
                      },

                      icon:
                          const Icon(
                        Icons.settings,
                      ),

                      label:
                          const Text(
                        "Buka Pengaturan",
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    TextButton(
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pop();
                      },

                      child:
                          const Text(
                        "Kembali",
                      ),
                    ),
                  ],
                ),
              );
            },

            overlayBuilder:
                (context,
                    constraints) {
              final size =
                  constraints
                      .biggest;

              final boxSize =
                  size.shortestSide *
                      0.70;

              return Center(
                child: SizedBox(
                  width: boxSize,
                  height: boxSize,

                  child:
                      DecoratedBox(
                    decoration:
                        BoxDecoration(
                      border:
                          Border.all(
                        color:
                            const Color(
                          0xFF89B4FA,
                        ),
                        width: 3,
                      ),

                      borderRadius:
                          BorderRadius
                              .circular(
                        20,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          Positioned(
            left: 24,
            right: 24,
            bottom: 30,

            child:
                IgnorePointer(
              child:
                  Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),

                decoration:
                    BoxDecoration(
                  color: Colors.black
                      .withValues(
                    alpha: 0.70,
                  ),

                  borderRadius:
                      BorderRadius
                          .circular(
                    14,
                  ),
                ),

                child:
                    const Text(
                  "Arahkan kamera ke QR Code PyClean di PC",

                  textAlign:
                      TextAlign.center,

                  style:
                      TextStyle(
                    color:
                        Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ArHologramWidget
    extends StatefulWidget {
  final bool isDir;

  const ArHologramWidget({
    super.key,
    required this.isDir,
  });

  @override
  State<ArHologramWidget>
      createState() =>
          _ArHologramWidgetState();
}

class _ArHologramWidgetState
    extends State<ArHologramWidget>
    with
        SingleTickerProviderStateMixin {
  late AnimationController
      _controller;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(
      vsync: this,
      duration:
          const Duration(
        seconds: 5,
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildCubeFace(
    Color color,
    Matrix4 transform,
  ) {
    const double faceSize =
        85.0;

    return Transform(
      transform: transform,
      alignment:
          Alignment.center,

      child: Container(
        width: faceSize,
        height: faceSize,

        decoration:
            BoxDecoration(
          color:
              color.withValues(
            alpha: 0.85,
          ),

          border:
              Border.all(
            color:
                const Color(
              0xFFF9E2AF,
            ),
            width: 2.0,
          ),

          boxShadow: [
            BoxShadow(
              color:
                  const Color(
                0xFFF9E2AF,
              ).withValues(
                alpha: 0.4,
              ),

              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePaneFace(
    Color color,
    Matrix4 transform, {
    bool isFront = false,
  }) {
    const double paneWidth =
        85.0;

    const double paneHeight =
        115.0;

    return Transform(
      transform: transform,
      alignment:
          Alignment.center,

      child: Container(
        width: paneWidth,
        height: paneHeight,

        padding:
            const EdgeInsets.all(
          12,
        ),

        decoration:
            BoxDecoration(
          color:
              color.withValues(
            alpha: 0.35,
          ),

          borderRadius:
              BorderRadius.circular(
            6,
          ),

          border:
              Border.all(
            color:
                const Color(
              0xFF89B4FA,
            ),
            width: 1.8,
          ),

          boxShadow: [
            BoxShadow(
              color:
                  const Color(
                0xFF89B4FA,
              ).withValues(
                alpha: 0.3,
              ),

              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),

        child: isFront
            ? Column(
                mainAxisAlignment:
                    MainAxisAlignment
                        .center,

                children: [
                  const Icon(
                    Icons.description,
                    color:
                        Color(
                      0xFF89B4FA,
                    ),
                    size: 36,
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  Container(
                    height: 3,
                    width: 40,
                    color:
                        Colors.white38,
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Container(
                    height: 3,
                    width: 30,
                    color:
                        Colors.white24,
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Container(
                    height: 3,
                    width: 35,
                    color:
                        Colors.white24,
                  ),
                ],
              )
            : null,
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AnimatedBuilder(
      animation:
          _controller,

      builder:
          (context, child) {
        double angle =
            _controller.value *
                2 *
                pi;

        return SizedBox(
          height: 180,
          width: 180,

          child: Center(
            child: widget.isDir
                ? Transform(
                    transform:
                        Matrix4.identity()
                          ..setEntry(
                            3,
                            2,
                            0.0018,
                          )
                          ..rotateX(
                            0.4,
                          )
                          ..rotateY(
                            angle,
                          )
                          ..rotateZ(
                            0.1,
                          ),

                    alignment:
                        Alignment.center,

                    child: Stack(
                      children: [
                        _buildCubeFace(
                          Colors.amber
                              .shade800,

                          Matrix4
                              .identity()
                            ..translate(
                              0.0,
                              0.0,
                              -42.5,
                            ),
                        ),

                        _buildCubeFace(
                          Colors.amber
                              .shade700,

                          Matrix4
                              .identity()
                            ..rotateY(
                              pi / 2,
                            )
                            ..translate(
                              0.0,
                              0.0,
                              -42.5,
                            ),
                        ),

                        _buildCubeFace(
                          Colors.amber
                              .shade700,

                          Matrix4
                              .identity()
                            ..rotateY(
                              -pi / 2,
                            )
                            ..translate(
                              0.0,
                              0.0,
                              -42.5,
                            ),
                        ),

                        _buildCubeFace(
                          Colors.amber
                              .shade400,

                          Matrix4
                              .identity()
                            ..rotateX(
                              pi / 2,
                            )
                            ..translate(
                              0.0,
                              0.0,
                              -42.5,
                            ),
                        ),

                        _buildCubeFace(
                          Colors.amber
                              .shade900,

                          Matrix4
                              .identity()
                            ..rotateX(
                              -pi / 2,
                            )
                            ..translate(
                              0.0,
                              0.0,
                              -42.5,
                            ),
                        ),

                        _buildCubeFace(
                          Colors.amber
                              .shade300,

                          Matrix4
                              .identity()
                            ..translate(
                              0.0,
                              0.0,
                              42.5,
                            ),
                        ),
                      ],
                    ),
                  )
                : Transform(
                    transform:
                        Matrix4.identity()
                          ..setEntry(
                            3,
                            2,
                            0.0018,
                          )
                          ..rotateX(
                            0.3,
                          )
                          ..rotateY(
                            angle,
                          )
                          ..rotateZ(
                            0.05,
                          ),

                    alignment:
                        Alignment.center,

                    child: Stack(
                      children: [
                        _buildFilePaneFace(
                          const Color(
                            0xFF89B4FA,
                          ),

                          Matrix4
                              .identity()
                            ..translate(
                              0.0,
                              0.0,
                              -3.0,
                            ),
                        ),

                        _buildFilePaneFace(
                          const Color(
                            0xFF89B4FA,
                          ),

                          Matrix4
                              .identity()
                            ..translate(
                              0.0,
                              0.0,
                              3.0,
                            ),

                          isFront: true,
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}
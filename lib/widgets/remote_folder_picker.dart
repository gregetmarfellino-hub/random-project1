import 'package:flutter/material.dart';

import '../services/pyclean_api.dart';

class RemoteFolderPickerDialog extends StatefulWidget {
  const RemoteFolderPickerDialog({
    super.key,
    required this.api,
    required this.initialPath,
    this.blockedPath,
  });

  final PyCleanApi api;
  final String initialPath;
  final String? blockedPath;

  @override
  State<RemoteFolderPickerDialog> createState() =>
      _RemoteFolderPickerDialogState();
}

class _RemoteFolderPickerDialogState
    extends State<RemoteFolderPickerDialog> {
  String currentPath = '';
  String parentPath = '';
  List<dynamic> directories = const [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _load(widget.initialPath);
  }

  String _normalized(String path) {
    return path.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/').toLowerCase();
  }

  bool _samePath(String first, String second) {
    return _normalized(first) == _normalized(second);
  }

  Future<void> _load(String? path) async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final result = await widget.api.browse(path);
      if (!mounted) return;

      if (!result.isSuccess) {
        setState(() {
          isLoading = false;
          errorMessage = 'Folder PC tidak dapat dibuka.';
        });
        return;
      }

      final blocked = widget.blockedPath;
      final folders = result.items.where((item) {
        if (item is! Map) return false;
        if (item['is_dir'] != true) return false;

        final itemPath = (item['path'] ?? '').toString();
        if (blocked != null && blocked.isNotEmpty && _samePath(itemPath, blocked)) {
          return false;
        }

        return true;
      }).toList();

      setState(() {
        currentPath = result.currentPath;
        parentPath = result.parentPath;
        directories = folders;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = 'Gagal membuka folder: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canGoUp =
        currentPath.isNotEmpty &&
        parentPath.isNotEmpty &&
        !_samePath(currentPath, parentPath);

    return AlertDialog(
      backgroundColor: const Color(0xFF21222C),
      title: const Row(
        children: [
          Icon(
            Icons.drive_file_move_outline,
            color: Color(0xFF89B4FA),
          ),
          SizedBox(width: 10),
          Text('Pilih Folder Tujuan'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 430,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF181825),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Folder atas',
                    onPressed: canGoUp && !isLoading
                        ? () => _load(parentPath)
                        : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  Expanded(
                    child: Text(
                      currentPath.isEmpty ? 'Memuat...' : currentPath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFFA6E3A1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : errorMessage != null
                      ? Center(
                          child: Text(
                            errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        )
                      : directories.isEmpty
                          ? const Center(
                              child: Text(
                                'Tidak ada sub-folder di sini.',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          : ListView.builder(
                              itemCount: directories.length,
                              itemBuilder: (context, index) {
                                final item = directories[index] as Map;
                                final name = (item['name'] ?? '').toString();
                                final path = (item['path'] ?? '').toString();

                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.folder,
                                    color: Color(0xFF89B4FA),
                                  ),
                                  title: Text(name),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _load(path),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: currentPath.isEmpty || isLoading
              ? null
              : () => Navigator.pop(context, currentPath),
          icon: const Icon(Icons.check),
          label: const Text('Pindah ke sini'),
        ),
      ],
    );
  }
}

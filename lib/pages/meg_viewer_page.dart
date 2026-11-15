import 'package:file_picker/file_picker.dart';
import 'package:glyphxtools/files/meg/mega_file.dart';
import 'package:glyphxtools/files/meg/mega_file_archive.dart';
import 'package:glyphxtools/widgets/mega_directory_tree.dart';
import 'package:glyphxtools/widgets/mega_file_explorer.dart';
import 'package:glyphxtools/widgets/mega_file_viewer.dart';
import 'package:material_ui/material_ui.dart';

class MegViewerPage extends StatefulWidget {
  const MegViewerPage({super.key});

  @override
  State<MegViewerPage> createState() => _MegViewerPageState();
}

class _MegViewerPageState extends State<MegViewerPage> {
  MegaFileArchive? _archive;
  MegaDirectory? _directoryTree;

  MegaArchiveFile? _selectedFile;
  MegaFile? _loadedFile;

  String? _fileName;
  String? _previewError;

  bool _sidebarCollapsed = false;
  bool _isLoadingFile = false;

  Future<void> openMegaFile() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['meg'],
      );

      if (!mounted || files.isEmpty) {
        return;
      }

      final PlatformFile file = files.single;

      final MegaFileArchive archive = await MegaFileArchive.fromStream(
        file.readAsByteStream(),
        streamFactory: () => file.readAsByteStream(),
      );
      final MegaDirectory directoryTree = buildMegaDirectoryTree(archive);

      if (!mounted) {
        return;
      }

      setState(() {
        _archive = archive;
        _directoryTree = directoryTree;
        _fileName = file.name;

        _selectedFile = null;
        _loadedFile = null;
        _previewError = null;
      });
    } catch (error) {
      _showError('Failed to open MEG file: $error');
    }
  }

  Future<void> _selectFile(MegaArchiveFile? file) async {
    // Folder navigation clears the current preview.
    if (file == null) {
      setState(() {
        _selectedFile = null;
        _loadedFile = null;
        _previewError = null;
      });
      return;
    }

    // Avoid overlapping reads from the sequential archive reader.
    if (_isLoadingFile || _archive == null) {
      return;
    }

    setState(() {
      _selectedFile = file;
      _loadedFile = null;
      _previewError = null;
      _isLoadingFile = true;
    });

    try {
      final MegaFile loadedFile = await _archive!.readFile(file.record);

      if (!mounted || !identical(_selectedFile, file)) {
        return;
      }

      setState(() {
        _loadedFile = loadedFile;
      });
    } catch (error) {
      if (!mounted || !identical(_selectedFile, file)) {
        return;
      }

      setState(() {
        _previewError = 'Failed to read file: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFile = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildPreview() {
    if (_isLoadingFile) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Reading file from archive...'),
          ],
        ),
      );
    }

    if (_previewError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(_previewError!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_loadedFile != null) {
      return MegaFileViewer(file: _loadedFile!);
    }

    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 48),
          SizedBox(height: 12),
          Text('Select a file to preview it.'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasArchive = _archive != null;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MEG Viewer',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fileName ??
                          'Browse and inspect Empire at War MEG archives.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _isLoadingFile ? null : openMegaFile,
                icon: const Icon(Icons.folder_open),
                label: Text(hasArchive ? 'Open Another MEG' : 'Open MEG File'),
              ),
            ],
          ),

          const SizedBox(height: 24),

          Expanded(
            child: _directoryTree == null
                ? const Center(
                    child: Text('Open a .meg archive to inspect its contents.'),
                  )
                : Column(
                    children: [
                      // File explorer toolbar.
                      Row(
                        children: [
                          IconButton(
                            tooltip: _sidebarCollapsed
                                ? 'Show file sidebar'
                                : 'Hide file sidebar',
                            onPressed: () {
                              setState(() {
                                _sidebarCollapsed = !_sidebarCollapsed;
                              });
                            },
                            icon: Icon(
                              _sidebarCollapsed ? Icons.menu_open : Icons.menu,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedFile?.path ?? 'Archive contents',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Collapsible file sidebar.
                            if (!_sidebarCollapsed) ...[
                              SizedBox(
                                width: 300,
                                child: MegaFileExplorer(
                                  root: _directoryTree!,
                                  onFileSelected: (MegaArchiveFile? file) {
                                    _selectFile(file);
                                  },
                                ),
                              ),
                              const VerticalDivider(width: 1),
                            ],

                            // File preview.
                            Expanded(child: _buildPreview()),
                          ],
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

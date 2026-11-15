import 'package:glyphxtools/files/meg/mega_file_archive.dart';
import 'package:glyphxtools/widgets/mega_directory_tree.dart';
import 'package:glyphxtools/widgets/mega_file_explorer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';

class MegViewerPage extends StatefulWidget {
  const MegViewerPage({super.key});

  @override
  State<MegViewerPage> createState() => _MegViewerPageState();
}

class _MegViewerPageState extends State<MegViewerPage> {
  MegaFileArchive? _archive;
  String? _fileName;
  MegaDirectory? _directoryTree;
  MegaArchiveFile? _selectedFile;
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
      );

      final MegaDirectory directoryTree = buildMegaDirectoryTree(archive);

      setState(() {
        _archive = archive;
        _directoryTree = directoryTree;
        _fileName = file.name;
        _selectedFile = null;
      });
    } catch (error) {
      _showError('Failed to open MEG file: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
                onPressed: openMegaFile,
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
                : Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Folder tree + file listing
                        Expanded(
                          flex: 3,
                          child: MegaFileExplorer(
                            root: _directoryTree!,
                            onFileSelected: (MegaArchiveFile? file) {
                              setState(() {
                                _selectedFile = file;
                              });
                            },
                          ),
                        ),

                        const VerticalDivider(width: 1),

                        // File details
                        Expanded(
                          flex: 2,
                          child: _selectedFile == null
                              ? const Center(
                                  child: Text('Select a file to inspect it.'),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedFile!.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium,
                                      ),
                                      const SizedBox(height: 16),
                                      Text('Path: ${_selectedFile!.path}'),
                                      Text(
                                        'Size: ${_selectedFile!.record.size} bytes',
                                      ),
                                      Text('CRC: ${_selectedFile!.record.crc}'),
                                      Text(
                                        'Offset: ${_selectedFile!.record.start}',
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

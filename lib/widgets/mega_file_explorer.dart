
import 'package:material_ui/material_ui.dart';
import 'package:glyphxtools/widgets/mega_directory_tree.dart';

class MegaFileExplorer extends StatefulWidget {
  const MegaFileExplorer({
    super.key,
    required this.root,
    required this.onFileSelected,
  });

  final MegaDirectory root;
  final ValueChanged<MegaArchiveFile?> onFileSelected;

  @override
  State<MegaFileExplorer> createState() => _MegaFileExplorerState();
}

class _MegaFileExplorerState extends State<MegaFileExplorer> {
  late MegaDirectory _currentDirectory;

  final List<MegaDirectory> _parents = [];
  final TextEditingController _searchController =
      TextEditingController();

  final Map<MegaDirectory, List<_ExplorerEntry>> _entryCache = {};

  MegaArchiveFile? _selectedFile;

  @override
  void initState() {
    super.initState();
    _currentDirectory = widget.root;
  }

  @override
  void didUpdateWidget(covariant MegaFileExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.root, widget.root)) {
      _currentDirectory = widget.root;
      _parents.clear();
      _entryCache.clear();
      _selectedFile = null;
      _searchController.clear();
    }
  }

  List<_ExplorerEntry> get _allEntries {
    return _entryCache.putIfAbsent(_currentDirectory, () {
      final List<_ExplorerEntry> entries = [];

      for (final MapEntry<String, MegaDirectory> directory
          in _currentDirectory.directories.entries) {
        entries.add(
          _ExplorerEntry.directory(directory.value),
        );
      }

      for (final MegaArchiveFile file in _currentDirectory.files) {
        entries.add(
          _ExplorerEntry.file(file),
        );
      }

      entries.sort((a, b) {
        if (a.directory != null && b.file != null) {
          return -1;
        }

        if (a.file != null && b.directory != null) {
          return 1;
        }

        return a.name.toLowerCase().compareTo(
              b.name.toLowerCase(),
            );
      });

      return entries;
    });
  }

  List<_ExplorerEntry> get _visibleEntries {
    final String query =
        _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      return _allEntries;
    }

    return _allEntries
        .where((entry) => entry.name.toLowerCase().contains(query))
        .toList();
  }

  String get _currentPath {
    final List<String> parts = _parents
        .map((directory) => directory.name)
        .where((name) => name.isNotEmpty)
        .toList();

    if (_currentDirectory.name.isNotEmpty) {
      parts.add(_currentDirectory.name);
    }

    return parts.isEmpty ? 'Archive' : 'Archive / ${parts.join(' / ')}';
  }

  void _goUp() {
    if (_parents.isEmpty) {
      return;
    }

    setState(() {
      _currentDirectory = _parents.removeLast();
      _selectedFile = null;
      _searchController.clear();
    });

    widget.onFileSelected(null);
  }

  void _openDirectory(MegaDirectory directory) {
    setState(() {
      _parents.add(_currentDirectory);
      _currentDirectory = directory;
      _selectedFile = null;
      _searchController.clear();
    });

    widget.onFileSelected(null);
  }

  void _selectFile(MegaArchiveFile file) {
    setState(() {
      _selectedFile = file;
    });

    widget.onFileSelected(file);
  }

  IconData _fileIcon(String name) {
    final String extension = name.contains('.')
        ? name.substring(name.lastIndexOf('.')).toLowerCase()
        : '';

    switch (extension) {
      case '.dds':
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.bmp':
        return Icons.image_outlined;

      case '.txt':
      case '.ini':
      case '.cfg':
      case '.xml':
      case '.json':
        return Icons.description_outlined;

      case '.wav':
      case '.mp3':
      case '.ogg':
        return Icons.audio_file_outlined;

      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<_ExplorerEntry> entries = _visibleEntries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Go up',
                onPressed: _parents.isEmpty ? null : _goUp,
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(
                child: Text(
                  _currentPath,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search this folder...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
        ),

        const Divider(height: 1),

        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    _searchController.text.isEmpty
                        ? 'This folder is empty.'
                        : 'No matching files.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemExtent: 42,
                  scrollCacheExtent: ScrollCacheExtent.pixels(400),
                  itemBuilder: (context, index) {
                    final _ExplorerEntry entry = entries[index];
                    final bool isDirectory =
                        entry.directory != null;
                    final bool isSelected =
                        identical(_selectedFile, entry.file);

                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      selected: isSelected,
                      leading: Icon(
                        isDirectory
                            ? Icons.folder_outlined
                            : _fileIcon(entry.name),
                        size: 20,
                      ),
                      title: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isDirectory
                          ? const Icon(
                              Icons.chevron_right,
                              size: 18,
                            )
                          : null,
                      onTap: () {
                        if (entry.directory != null) {
                          _openDirectory(entry.directory!);
                        } else if (entry.file != null) {
                          _selectFile(entry.file!);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ExplorerEntry {
   _ExplorerEntry.directory(MegaDirectory value)
      : directory = value,
        file = null,
        name = value.name;

   _ExplorerEntry.file(MegaArchiveFile value)
      : directory = null,
        file = value,
        name = value.name;

  final String name;
  final MegaDirectory? directory;
  final MegaArchiveFile? file;
}

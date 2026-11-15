
import 'package:glyphxtools/widgets/mega_directory_tree.dart';
import 'package:material_ui/material_ui.dart';

class MegaFileExplorer extends StatefulWidget {
  const MegaFileExplorer({
    super.key,
    required this.root,
    this.onFileSelected,
  });

  final MegaDirectory root;
  final ValueChanged<MegaArchiveFile?>? onFileSelected;

  @override
  State<MegaFileExplorer> createState() => _MegaFileExplorerState();
}

class _MegaFileExplorerState extends State<MegaFileExplorer> {
  final List<MegaDirectory> _directoryStack = [];
  final Set<MegaDirectory> _expandedDirectories = {};

  final Map<MegaDirectory, List<MegaDirectory>> _directoryCache = {};
  final Map<MegaDirectory, List<_ExplorerEntry>> _entryCache = {};

  final TextEditingController _searchController =
      TextEditingController();

  String _searchQuery = '';
  MegaArchiveFile? _selectedFile;

  MegaDirectory get _currentDirectory =>
      _directoryStack.isEmpty ? widget.root : _directoryStack.last;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Sort each directory only once.
  List<MegaDirectory> _sortedDirectories(MegaDirectory directory) {
    return _directoryCache.putIfAbsent(directory, () {
      final List<MegaDirectory> result =
          directory.directories.values.toList();

      result.sort(
        (a, b) => a.name.toLowerCase().compareTo(
              b.name.toLowerCase(),
            ),
      );

      return result;
    });
  }

  // Create and cache the sorted entries for each directory.
  List<_ExplorerEntry> _entriesFor(MegaDirectory directory) {
    return _entryCache.putIfAbsent(directory, () {
      final List<_ExplorerEntry> entries = [];

      for (final MegaDirectory child
          in _sortedDirectories(directory)) {
        entries.add(_ExplorerEntry.directory(child));
      }

      final List<MegaArchiveFile> files =
          List<MegaArchiveFile>.of(directory.files);

      files.sort(
        (a, b) => a.name.toLowerCase().compareTo(
              b.name.toLowerCase(),
            ),
      );

      for (final MegaArchiveFile file in files) {
        entries.add(_ExplorerEntry.file(file));
      }

      return entries;
    });
  }

  // Flatten only expanded folders for the folder tree.
  // ListView.builder will still build only visible rows.
  List<_FolderRow> _visibleFolderRows() {
    final List<_FolderRow> result = [];

    void addChildren(
      MegaDirectory parent,
      List<MegaDirectory> parentPath,
      int depth,
    ) {
      for (final MegaDirectory child
          in _sortedDirectories(parent)) {
        final List<MegaDirectory> path = [
          ...parentPath,
          child,
        ];

        result.add(
          _FolderRow(
            directory: child,
            path: path,
            depth: depth,
          ),
        );

        if (_expandedDirectories.contains(child)) {
          addChildren(child, path, depth + 1);
        }
      }
    }

    addChildren(widget.root, [], 0);

    return result;
  }

  void _selectFolder(List<MegaDirectory> path) {
    setState(() {
      _directoryStack
        ..clear()
        ..addAll(path);

      _expandedDirectories.addAll(path);

      _selectedFile = null;
      _clearSearch();
    });

    widget.onFileSelected?.call(null);
  }

  void _openDirectory(MegaDirectory directory) {
    setState(() {
      _directoryStack.add(directory);
      _expandedDirectories.addAll(_directoryStack);

      _selectedFile = null;
      _clearSearch();
    });

    widget.onFileSelected?.call(null);
  }

  void _navigateToBreadcrumb(int index) {
    setState(() {
      if (index < 0) {
        _directoryStack.clear();
      } else {
        _directoryStack.removeRange(
          index + 1,
          _directoryStack.length,
        );
      }

      _selectedFile = null;
      _clearSearch();
    });

    widget.onFileSelected?.call(null);
  }

  void _toggleDirectory(MegaDirectory directory) {
    setState(() {
      if (!_expandedDirectories.add(directory)) {
        _expandedDirectories.remove(directory);
      }
    });
  }

  void _selectFile(MegaArchiveFile file) {
    setState(() {
      _selectedFile = file;
    });

    widget.onFileSelected?.call(file);
  }

  void _clearSearch() {
    _searchController.clear();
    _searchQuery = '';
  }

  @override
  Widget build(BuildContext context) {
    final List<_FolderRow> folderRows = _visibleFolderRows();

    final List<_ExplorerEntry> allEntries =
        _entriesFor(_currentDirectory);

    final String query = _searchQuery.trim().toLowerCase();

    final List<_ExplorerEntry> visibleEntries = query.isEmpty
        ? allEntries
        : allEntries
            .where(
              (entry) => entry.name.toLowerCase().contains(query),
            )
            .toList(growable: false);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LEFT: Folder navigation tree
        SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(
                height: 44,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Folders',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: folderRows.length,
                  itemExtent: 36,
                  cacheExtent: 400,
                  addAutomaticKeepAlives: false,
                  itemBuilder: (context, index) {
                    final _FolderRow row = folderRows[index];

                    final bool selected =
                        identical(_currentDirectory, row.directory);

                    final bool expanded =
                        _expandedDirectories.contains(row.directory);

                    final bool hasChildren =
                        row.directory.directories.isNotEmpty;

                    final ColorScheme colors =
                        Theme.of(context).colorScheme;

                    return Padding(
                      padding: EdgeInsets.only(
                        left: 6 + row.depth * 14.0,
                        right: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => _selectFolder(row.path),
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? colors.secondaryContainer
                                      : null,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      expanded
                                          ? Icons.folder_open
                                          : Icons.folder,
                                      size: 19,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        row.directory.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            height: 32,
                            child: hasChildren
                                ? IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: expanded
                                        ? 'Collapse folder'
                                        : 'Expand folder',
                                    icon: Icon(
                                      expanded
                                          ? Icons.expand_more
                                          : Icons.chevron_right,
                                      size: 19,
                                    ),
                                    onPressed: () => _toggleDirectory(
                                      row.directory,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1),

        // RIGHT: Current directory contents
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Toolbar and breadcrumbs
              SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Go back',
                        onPressed: _directoryStack.isEmpty
                            ? null
                            : () => _navigateToBreadcrumb(
                                  _directoryStack.length - 2,
                                ),
                        icon: const Icon(Icons.arrow_back),
                      ),

                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              TextButton(
                                onPressed: () =>
                                    _navigateToBreadcrumb(-1),
                                child: const Text('Archive'),
                              ),
                              for (int i = 0;
                                  i < _directoryStack.length;
                                  i++) ...[
                                const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _navigateToBreadcrumb(i),
                                  child: Text(_directoryStack[i].name),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      SizedBox(
                        width: 200,
                        height: 36,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (String value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search this folder',
                            prefixIcon: const Icon(
                              Icons.search,
                              size: 19,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    tooltip: 'Clear search',
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      setState(_clearSearch);
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1),

              // Column headers
              SizedBox(
                height: 34,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const SizedBox(width: 28),
                      const Expanded(
                        child: Text(
                          'Name',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Text(
                          'Size',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1),

              // Virtualized file listing
              Expanded(
                child: visibleEntries.isEmpty
                    ? Center(
                        child: Text(
                          query.isEmpty
                              ? 'This folder is empty.'
                              : 'No matching files or folders.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: visibleEntries.length,
                        itemExtent: 44,
                        cacheExtent: 500,
                        addAutomaticKeepAlives: false,
                        itemBuilder: (context, index) {
                          final _ExplorerEntry entry =
                              visibleEntries[index];

                          final bool isDirectory =
                              entry.directory != null;

                          final MegaArchiveFile? file = entry.file;

                          final bool selected = file != null &&
                              identical(_selectedFile, file);

                          final ColorScheme colors =
                              Theme.of(context).colorScheme;

                          return InkWell(
                            key: ValueKey(
                              entry.directory ?? entry.file,
                            ),
                            onTap: isDirectory
                                ? () => _openDirectory(entry.directory!)
                                : () => _selectFile(file!),
                            child: Container(
                              color: selected
                                  ? colors.secondaryContainer
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Icon(
                                      isDirectory
                                          ? Icons.folder
                                          : _fileIcon(file!.name),
                                      size: 20,
                                      color: isDirectory
                                          ? colors.primary
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 100,
                                    child: Text(
                                      isDirectory
                                          ? ''
                                          : _formatSize(file!.record.size),
                                      textAlign: TextAlign.end,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              const Divider(height: 1),

              // Status bar
              SizedBox(
                height: 28,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${visibleEntries.length} items',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _fileIcon(String name) {
    final String extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';

    switch (extension) {
      case 'dds':
      case 'tga':
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'bmp':
        return Icons.image_outlined;

      case 'txt':
      case 'xml':
      case 'ini':
      case 'cfg':
      case 'lua':
        return Icons.description_outlined;

      case 'wav':
      case 'mp3':
        return Icons.audio_file_outlined;

      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ExplorerEntry {
  const _ExplorerEntry.directory(this.directory) : file = null;

  const _ExplorerEntry.file(this.file) : directory = null;

  final MegaDirectory? directory;
  final MegaArchiveFile? file;

  String get name => directory?.name ?? file!.name;
}

class _FolderRow {
  const _FolderRow({
    required this.directory,
    required this.path,
    required this.depth,
  });

  final MegaDirectory directory;
  final List<MegaDirectory> path;
  final int depth;
}

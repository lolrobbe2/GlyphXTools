import 'package:glyphxtools/files/meg/meg_file_table_record.dart';
import 'package:glyphxtools/files/meg/mega_file_archive.dart';

class MegaDirectory {
  MegaDirectory(this.name);

  final String name;

  final Map<String, MegaDirectory> directories = {};
  final List<MegaArchiveFile> files = [];
}

class MegaArchiveFile {
  MegaArchiveFile({
    required this.name,
    required this.path,
    required this.record,
  });

  final String name;
  final String path;
  final FileTableRecord record;
}

MegaDirectory buildMegaDirectoryTree(MegaFileArchive archive) {
  final MegaDirectory root = MegaDirectory('');

  for (final FileTableRecord record in archive.fileTableRecords) {
    if (record.name >= archive.filenameRecords.length) {
      throw FormatException(
        'Invalid filename index: ${record.name}',
      );
    }

    final String path = archive.filenameRecords[record.name]
        .fileName
        .replaceAll('\\', '/');

    final List<String> parts = path
        .split('/')
        .where((String part) => part.isNotEmpty && part != '.')
        .toList();

    if (parts.isEmpty) {
      continue;
    }

    MegaDirectory current = root;

    for (final String directoryName in parts.take(parts.length - 1)) {
      current = current.directories.putIfAbsent(
        directoryName,
        () => MegaDirectory(directoryName),
      );
    }

    current.files.add(
      MegaArchiveFile(
        name: parts.last,
        path: path,
        record: record,
      ),
    );
  }

  return root;
}
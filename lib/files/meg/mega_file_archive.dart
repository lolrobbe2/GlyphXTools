import 'dart:async';
import 'dart:typed_data';

import 'package:glyphxtools/files/meg/meg_file_table_record.dart';
import 'package:glyphxtools/files/meg/meg_filename_table_record.dart';
import 'package:glyphxtools/files/meg/mega_binary_reader.dart';
import 'package:glyphxtools/files/meg/mega_file.dart';

class MegaFileArchive {
  MegaFileArchive._(
    this.reader,
    this.numFilenames,
    this.numFiles,
    this.filenameRecords,
    this.fileTableRecords,
  );

  static Future<MegaFileArchive> fromStream(Stream<List<int>> stream) async {
    final MegaBinaryReader reader = MegaBinaryReader(stream);

    final int numFilenames = await reader.readUint32();
    final int numFiles = await reader.readUint32();
    final List<FilenameTableRecord> filenameRecords = new List.empty(
      growable: true,
    );
    final List<FileTableRecord> fileTableRecords = new List.empty(
      growable: true,
    );

    for (var i = 0; i < numFilenames; i++) {
      filenameRecords.add(await FilenameTableRecord.fromReader(reader));
    }

    for (var i = 0; i < numFiles; i++) {
      fileTableRecords.add(await FileTableRecord.fromReader(reader));
    }
    return MegaFileArchive._(
      reader,
      numFilenames,
      numFiles,
      filenameRecords,
      fileTableRecords,
    );
  }

  final MegaBinaryReader reader;

  //Number of filenames in the Filename Table
  final int numFilenames;

  //Number of files in the File Table
  final int numFiles;

  final List<FilenameTableRecord> filenameRecords;
  final List<FileTableRecord> fileTableRecords;

  Future<MegaFile> readFile(FileTableRecord record) async {
    if (record.name < 0 || record.name >= filenameRecords.length) {
      throw FormatException('Invalid filename index: ${record.name}');
    }

    final String path = filenameRecords[record.name].fileName;

    if (record.start < reader.position) {
      throw StateError(
        'Cannot read "$path": its data starts at ${record.start}, '
        'but the reader is already at ${reader.position}. '
        'The archive stream is sequential.',
      );
    }

    await reader.skip(record.start - reader.position);

    final Uint8List data = await reader.readBytes(record.size);

    return MegaFile(path: path, record: record, data: data);
  }
}

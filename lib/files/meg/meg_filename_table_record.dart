import 'dart:convert';

import 'package:glyphxtools/files/meg/mega_binary_reader.dart';

class FilenameTableRecord {
  FilenameTableRecord({
    required this.length,
    required this.fileName,
  });

  final int length;
  final String fileName;

  static Future<FilenameTableRecord> fromReader(
    MegaBinaryReader reader,
  ) async {
    final int length = await reader.readUint16();
    final List<int> bytes = await reader.readBytes(length);

    return FilenameTableRecord(
      length: length,
      fileName: utf8.decode(bytes),
    );
  }
}
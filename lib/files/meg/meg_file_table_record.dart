import 'package:glyphxtools/files/meg/mega_binary_reader.dart';

class FileTableRecord {
  FileTableRecord({
    required this.crc,
    required this.index,
    required this.size,
    required this.start,
    required this.name,
  });

  final int crc;
  final int index;
  final int size;
  final int start;
  final int name;

  static Future<FileTableRecord> fromReader(
    MegaBinaryReader reader,
  ) async {
    return FileTableRecord(
      crc: await reader.readUint32(),
      index: await reader.readUint32(),
      size: await reader.readUint32(),
      start: await reader.readUint32(),
      name: await reader.readUint32(),
    );
  }
}
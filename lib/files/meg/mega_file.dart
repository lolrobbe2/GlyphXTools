import 'dart:typed_data';

import 'package:glyphxtools/files/meg/meg_file_table_record.dart';

class MegaFile {
  const MegaFile({
    required this.path,
    required this.record,
    required this.data,
  });

  final String path;
  final FileTableRecord record;
  final Uint8List data;

  String get name => path.replaceAll('\\', '/').split('/').last;

  int get size => data.length;
}
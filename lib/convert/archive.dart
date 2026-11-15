import 'dart:typed_data';

import 'package:archive/archive.dart' as zip;
import 'package:glyphxtools/files/meg/mega_file_archive.dart';
import 'package:glyphxtools/files/meg/meg_file_table_record.dart';

typedef MegConversionProgressCallback = void Function({
  required String status,
  required double progress,
  required int completedFiles,
  required int totalFiles,
});

class MegToZipConverter {
  static const Set<String> _alreadyCompressedExtensions = {
    // Images
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.avif',
    '.heic', '.heif', '.jxl', '.jp2', '.dds'

    // Audio
    '.mp3', '.mp4', '.m4a', '.aac', '.ogg', '.opus',
    '.flac', '.wma',

    // Video
    '.mkv', '.avi', '.mov', '.wmv', '.webm', '.m4v',
    '.3gp',

    // Archives and compressed files
    '.zip', '.gz', '.gzip', '.7z', '.rar', '.bz2',
    '.xz', '.zst', '.lz4', '.br', '.tgz', '.tbz2',

    // ZIP-based document formats
    '.docx', '.xlsx', '.pptx', '.odt', '.ods', '.odp',
    '.epub',

    // Applications and packages
    '.apk', '.jar', '.war', '.aar', '.ipa', '.vsix',

    // Fonts
    '.woff', '.woff2',
  };

  static bool _shouldSkipCompression(String path) {
    final int slashIndex = path.lastIndexOf('/');
    final int dotIndex = path.lastIndexOf('.');

    if (dotIndex <= slashIndex) {
      return false;
    }

    final String extension = path.substring(dotIndex).toLowerCase();

    return _alreadyCompressedExtensions.contains(extension);
  }

  static Future<Uint8List> convert(
    MegaFileArchive megArchive, {
    MegConversionProgressCallback? onProgress,
  }) async {
    final zip.Archive zipArchive = zip.Archive();

    final List<FileTableRecord> records = List<FileTableRecord>.of(
      megArchive.fileTableRecords,
    )..sort((a, b) => a.start.compareTo(b.start));

    final int totalFiles = records.length;
    final int totalBytes = records.fold<int>(
      0,
      (total, record) => total + record.size,
    );

    int processedBytes = 0;

    for (int i = 0; i < records.length; i++) {
      final FileTableRecord record = records[i];

      final String path = megArchive.filenameRecords[record.name].fileName;

      final double previousProgress = totalBytes > 0
          ? processedBytes / totalBytes
          : (totalFiles > 0 ? i / totalFiles : 0.0);

      onProgress?.call(
        status: 'Reading $path',
        progress: 0.05 + (0.85 * previousProgress),
        completedFiles: i,
        totalFiles: totalFiles,
      );

      final megaFile = await megArchive.readFile(record);

      final String normalizedPath = megaFile.path.replaceAll('\\', '/');

      final List<String> pathParts = normalizedPath.split('/');

      if (normalizedPath.startsWith('/') ||
          pathParts.contains('..') ||
          RegExp(r'^[a-zA-Z]:').hasMatch(normalizedPath)) {
        throw FormatException('Invalid archive path: $normalizedPath');
      }

      final bool skipCompression = _shouldSkipCompression(normalizedPath);

      final zip.ArchiveFile zipFile;

      if (skipCompression) {
        zipFile = zip.ArchiveFile.noCompress(
          normalizedPath,
          megaFile.data.length,
          megaFile.data,
        );
      } else {
        zipFile = zip.ArchiveFile(
          normalizedPath,
          megaFile.data.length,
          megaFile.data,
        );
      }

      zipArchive.addFile(zipFile);

      processedBytes += megaFile.data.length;

      final double fileProgress = totalBytes > 0
          ? (processedBytes / totalBytes).clamp(0.0, 1.0).toDouble()
          : (totalFiles > 0 ? (i + 1) / totalFiles : 1.0);

      onProgress?.call(
        status: 'Processed ${i + 1} of $totalFiles files',
        progress: 0.05 + (0.85 * fileProgress),
        completedFiles: i + 1,
        totalFiles: totalFiles,
      );
    }

    onProgress?.call(
      status: 'Building ZIP archive...',
      progress: 0.95,
      completedFiles: totalFiles,
      totalFiles: totalFiles,
    );

    // Give Flutter an opportunity to render the finalizing status.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    final List<int> encoded = zip.ZipEncoder().encode(zipArchive);

    onProgress?.call(
      status: 'Conversion completed',
      progress: 1.0,
      completedFiles: totalFiles,
      totalFiles: totalFiles,
    );

    return Uint8List.fromList(encoded);
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:glyphxtools/files/meg/meg_file_table_record.dart';
import 'package:glyphxtools/files/meg/meg_filename_table_record.dart';
import 'package:glyphxtools/files/meg/mega_binary_reader.dart';
import 'package:glyphxtools/files/meg/mega_file.dart';

class MegaFileArchive {
  MegaFileArchive._(
    this._reader,
    this._streamFactory,
    this.numFilenames,
    this.numFiles,
    this.filenameRecords,
    this.fileTableRecords,
  );

  static Future<MegaFileArchive> fromStream(
    Stream<List<int>> stream, {
    required Stream<List<int>> Function() streamFactory,
  }) async {
    final MegaBinaryReader reader = MegaBinaryReader(stream);

    try {
      final int numFilenames = await reader.readUint32();
      final int numFiles = await reader.readUint32();

      final List<FilenameTableRecord> filenameRecords = [];
      final List<FileTableRecord> fileTableRecords = [];

      for (int i = 0; i < numFilenames; i++) {
        filenameRecords.add(
          await FilenameTableRecord.fromReader(reader),
        );
      }

      for (int i = 0; i < numFiles; i++) {
        fileTableRecords.add(
          await FileTableRecord.fromReader(reader),
        );
      }

      return MegaFileArchive._(
        reader,
        streamFactory,
        numFilenames,
        numFiles,
        filenameRecords,
        fileTableRecords,
      );
    } catch (error) {
      await reader.close();
      rethrow;
    }
  }

  MegaBinaryReader _reader;

  final Stream<List<int>> Function() _streamFactory;

  MegaBinaryReader get reader => _reader;

  final int numFilenames;
  final int numFiles;

  final List<FilenameTableRecord> filenameRecords;
  final List<FileTableRecord> fileTableRecords;

  Future<void> _readQueue = Future<void>.value();

  bool _closing = false;
  bool _closed = false;

  /// Reads a file from the archive.
  ///
  /// Files can be accessed in any order. If the requested file is
  /// behind the current reader position, the stream is reopened.
  ///
  /// Concurrent requests are serialized to protect the sequential reader.
  Future<MegaFile> readFile(FileTableRecord record) {
    if (_closing || _closed) {
      return Future<MegaFile>.error(
        StateError('MegaFileArchive is closed.'),
      );
    }

    final Completer<MegaFile> completer = Completer<MegaFile>();

    _readQueue = _readQueue.then((_) async {
      try {
        final MegaFile file = await _readFileInternal(record);
        completer.complete(file);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  Future<MegaFile> _readFileInternal(FileTableRecord record) async {
    if (_closed) {
      throw StateError('MegaFileArchive is closed.');
    }

    if (record.name < 0 || record.name >= filenameRecords.length) {
      throw FormatException(
        'Invalid filename index: ${record.name}',
      );
    }

    if (record.start < 0 || record.size < 0) {
      throw FormatException(
        'Invalid file offset or size: ${record.start}, ${record.size}',
      );
    }

    final String path = filenameRecords[record.name].fileName;

    // We need to restart the stream if the requested file is behind
    // the current reader position.
    if (record.start < _reader.position) {
      await _restartReader();
    }

    // Advance to the requested file.
    final int bytesToSkip = record.start - _reader.position;

    if (bytesToSkip > 0) {
      await _reader.skip(bytesToSkip);
    }

    // Read file contents.
    final Uint8List data = await _reader.readBytes(record.size);

    return MegaFile(
      path: path,
      record: record,
      data: data,
    );
  }

  /// Recreates the reader from the beginning of the MEG file.
  Future<void> _restartReader() async {
    final MegaBinaryReader newReader = MegaBinaryReader(
      _streamFactory(),
    );

    await _reader.close();

    _reader = newReader;
  }

  /// Closes the underlying stream.
  Future<void> close() async {
    if (_closing || _closed) {
      return;
    }

    _closing = true;

    await _readQueue;

    _closed = true;

    await _reader.close();
  }
}
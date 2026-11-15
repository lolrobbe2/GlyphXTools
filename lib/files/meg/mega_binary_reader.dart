import 'dart:async';
import 'dart:typed_data';

class MegaBinaryReader {
  MegaBinaryReader(Stream<List<int>> stream)
      : _iterator = StreamIterator<List<int>>(stream);

  final StreamIterator<List<int>> _iterator;

  List<int>? _chunk;

  int _chunkOffset = 0;
  int _position = 0;

  bool _closed = false;
  bool _eof = false;

  int get position => _position;

  /// Reads one unsigned byte.
  Future<int> readUint8() async {
    await _ensureChunk();

    final int value = _chunk![_chunkOffset];

    _chunkOffset++;
    _position++;

    return value;
  }

  /// Reads an unsigned 16-bit integer.
  Future<int> readUint16({
    Endian endian = Endian.little,
  }) {
    return _readUnsigned(2, endian);
  }

  /// Reads an unsigned 32-bit integer.
  Future<int> readUint32({
    Endian endian = Endian.little,
  }) {
    return _readUnsigned(4, endian);
  }

  /// Reads [count] bytes into a new Uint8List.
  Future<Uint8List> readBytes(int count) async {
    if (count < 0) {
      throw RangeError.value(count, 'count');
    }

    final Uint8List result = Uint8List(count);

    int copied = 0;

    while (copied < count) {
      await _ensureChunk();

      final List<int> chunk = _chunk!;

      final int available = chunk.length - _chunkOffset;

      final int remaining = count - copied;

      final int amount = available < remaining
          ? available
          : remaining;

      result.setRange(
        copied,
        copied + amount,
        chunk,
        _chunkOffset,
      );

      _chunkOffset += amount;
      _position += amount;
      copied += amount;
    }

    return result;
  }

  /// Advances the reader without allocating or copying bytes.
  Future<void> skip(int count) async {
    if (count < 0) {
      throw RangeError.value(count, 'count');
    }

    int remaining = count;

    while (remaining > 0) {
      await _ensureChunk();

      final List<int> chunk = _chunk!;

      final int available = chunk.length - _chunkOffset;

      final int amount = available < remaining
          ? available
          : remaining;

      _chunkOffset += amount;
      _position += amount;
      remaining -= amount;
    }
  }

  /// Reads an unsigned integer directly from the current chunk
  /// whenever possible, without allocating a temporary buffer.
  Future<int> _readUnsigned(int byteCount, Endian endian) async {
    await _ensureChunk();

    final List<int> chunk = _chunk!;

    final int available = chunk.length - _chunkOffset;

    // Fast path: all bytes are in the current chunk.
    if (available >= byteCount) {
      final int offset = _chunkOffset;

      int value = 0;

      if (endian == Endian.little) {
        for (int i = 0; i < byteCount; i++) {
          value |= chunk[offset + i] << (i * 8);
        }
      } else {
        for (int i = 0; i < byteCount; i++) {
          value = (value << 8) | chunk[offset + i];
        }
      }

      _chunkOffset += byteCount;
      _position += byteCount;

      return value;
    }

    // Slow path: the integer spans multiple stream chunks.
    int value = 0;

    if (endian == Endian.little) {
      for (int i = 0; i < byteCount; i++) {
        value |= (await readUint8()) << (i * 8);
      }
    } else {
      for (int i = 0; i < byteCount; i++) {
        value = (value << 8) | await readUint8();
      }
    }

    return value;
  }

  /// Ensures that the current chunk contains at least one byte.
  Future<void> _ensureChunk() async {
    if (_closed) {
      throw StateError('MegaBinaryReader is closed');
    }

    while (_chunk == null || _chunkOffset >= _chunk!.length) {
      if (_eof) {
        throw const FormatException('Unexpected end of MEG file');
      }

      if (!await _iterator.moveNext()) {
        _eof = true;
        throw const FormatException('Unexpected end of MEG file');
      }

      _chunk = _iterator.current;
      _chunkOffset = 0;
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;
    _chunk = null;

    await _iterator.cancel();
  }
}
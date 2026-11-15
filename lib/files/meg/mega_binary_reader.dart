import 'dart:async';
import 'dart:typed_data';

class MegaBinaryReader {
  MegaBinaryReader(Stream<List<int>> stream)
      : _iterator = StreamIterator<List<int>>(stream);

  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = [];

  bool _closed = false;

  Future<int> readUint8() async {
    await _ensureAvailable(1);

    return _buffer.removeAt(0);
  }

  Future<int> readUint16({
    Endian endian = Endian.little,
  }) async {
    final Uint8List bytes = await _readBytes(2);

    return ByteData.sublistView(bytes).getUint16(0, endian);
  }

  Future<int> readUint32({
    Endian endian = Endian.little,
  }) async {
    final Uint8List bytes = await _readBytes(4);

    return ByteData.sublistView(bytes).getUint32(0, endian);
  }

  Future<Uint8List> readBytes(int count) async {
    return _readBytes(count);
  }

  Future<Uint8List> _readBytes(int count) async {
    await _ensureAvailable(count);

    final Uint8List result = Uint8List.fromList(
      _buffer.sublist(0, count),
    );

    _buffer.removeRange(0, count);

    return result;
  }

  Future<void> _ensureAvailable(int count) async {
    while (_buffer.length < count) {
      if (!await _iterator.moveNext()) {
        throw const FormatException('Unexpected end of MEG file');
      }

      _buffer.addAll(_iterator.current);
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;
    await _iterator.cancel();
  }
}
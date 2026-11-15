import 'dart:typed_data';

class DdsDecodedPixels {
  const DdsDecodedPixels({
    required this.width,
    required this.height,
    required this.rgba,
    required this.format,
  });

  final int width;
  final int height;
  final Uint8List rgba;
  final String format;
}

DdsDecodedPixels decodeDdsPixels(Uint8List data) {
  if (data.length < 128) {
    throw const FormatException('DDS file is too small.');
  }

  final ByteData header = ByteData.sublistView(data);

  int uint32(int offset) {
    return header.getUint32(offset, Endian.little);
  }

  if (uint32(0) != 0x20534444) {
    throw const FormatException('Invalid DDS magic.');
  }

  if (uint32(4) != 124) {
    throw const FormatException('Invalid DDS header size.');
  }

  final int height = uint32(12);
  final int width = uint32(16);

  if (width <= 0 ||
      height <= 0 ||
      width > 16384 ||
      height > 16384 ||
      width * height > 64 * 1024 * 1024) {
    throw const FormatException('Invalid or excessively large DDS dimensions.');
  }

  final int pitch = uint32(20);
  final int fourCC = uint32(84);
  final int pixelFlags = uint32(80);

  String format;
  int dataOffset = 128;

  switch (fourCC) {
    case 0x31545844: // DXT1
      format = 'BC1';
      break;

    case 0x33545844: // DXT3
      format = 'BC2';
      break;

    case 0x35545844: // DXT5
      format = 'BC3';
      break;

    case 0x31495441: // ATI1
    case 0x55344342: // BC4U
      format = 'BC4';
      break;

    case 0x32495441: // ATI2
    case 0x55354342: // BC5U
      format = 'BC5';
      break;

    case 0x30315844: // DX10
      if (data.length < 148) {
        throw const FormatException('Missing DDS DX10 header.');
      }

      dataOffset = 148;

      switch (uint32(128)) {
        case 71:
        case 72:
          format = 'BC1';
          break;
        case 74:
        case 75:
          format = 'BC2';
          break;
        case 77:
        case 78:
          format = 'BC3';
          break;
        case 80:
          format = 'BC4';
          break;
        case 83:
          format = 'BC5';
          break;
        case 28:
        case 29:
          format = 'RGBA32';
          break;
        case 87:
        case 91:
          format = 'BGRA32';
          break;
        default:
          throw FormatException(
            'Unsupported DDS DXGI format: ${uint32(128)}',
          );
      }
      break;

    default:
      if ((pixelFlags & 0x4) != 0) {
        throw FormatException(
          'Unsupported DDS FourCC: 0x${fourCC.toRadixString(16)}',
        );
      }

      if ((pixelFlags & 0x40) == 0) {
        throw const FormatException('Unsupported DDS pixel format.');
      }

      format = 'RGB';
  }

  final Uint8List rgba = Uint8List(width * height * 4);

  switch (format) {
    case 'BC1':
      _decodeBlocks(data, dataOffset, rgba, width, height, format);
      break;
    case 'BC2':
      _decodeBlocks(data, dataOffset, rgba, width, height, format);
      break;
    case 'BC3':
      _decodeBlocks(data, dataOffset, rgba, width, height, format);
      break;
    case 'BC4':
      _decodeBlocks(data, dataOffset, rgba, width, height, format);
      break;
    case 'BC5':
      _decodeBlocks(data, dataOffset, rgba, width, height, format);
      break;
    case 'RGBA32':
    case 'BGRA32':
      _decode32Bit(data, dataOffset, rgba, width, height, format);
      break;
    case 'RGB':
      _decodeMaskedRgb(
        data,
        dataOffset,
        rgba,
        width,
        height,
        pitch,
        uint32(88),
        uint32(92),
        uint32(96),
        uint32(100),
        uint32(104),
      );
      format = 'RGB ${uint32(88)}-bit';
      break;
  }

  return DdsDecodedPixels(
    width: width,
    height: height,
    rgba: rgba,
    format: format,
  );
}

void _decode32Bit(
  Uint8List data,
  int offset,
  Uint8List output,
  int width,
  int height,
  String format,
) {
  final int required = width * height * 4;

  if (offset + required > data.length) {
    throw const FormatException('DDS pixel data is incomplete.');
  }

  for (int i = 0; i < width * height; i++) {
    final int source = offset + i * 4;
    final int destination = i * 4;

    if (format == 'RGBA32') {
      output[destination] = data[source];
      output[destination + 1] = data[source + 1];
      output[destination + 2] = data[source + 2];
    } else {
      output[destination] = data[source + 2];
      output[destination + 1] = data[source + 1];
      output[destination + 2] = data[source];
    }

    output[destination + 3] = data[source + 3];
  }
}

void _decodeMaskedRgb(
  Uint8List data,
  int offset,
  Uint8List output,
  int width,
  int height,
  int pitch,
  int bits,
  int redMask,
  int greenMask,
  int blueMask,
  int alphaMask,
) {
  if (bits != 16 && bits != 24 && bits != 32) {
    throw FormatException('Unsupported RGB bit depth: $bits');
  }

  final int bytesPerPixel = bits ~/ 8;
  final int minimumPitch = width * bytesPerPixel;
  final int rowPitch = pitch >= minimumPitch ? pitch : minimumPitch;

  if (offset + rowPitch * height > data.length) {
    throw const FormatException('DDS pixel data is incomplete.');
  }

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int source = offset + y * rowPitch + x * bytesPerPixel;

      int pixel = 0;

      for (int i = 0; i < bytesPerPixel; i++) {
        pixel |= data[source + i] << (i * 8);
      }

      final int destination = (y * width + x) * 4;

      output[destination] =
          _extractChannel(pixel, redMask, 0);
      output[destination + 1] =
          _extractChannel(pixel, greenMask, 0);
      output[destination + 2] =
          _extractChannel(pixel, blueMask, 0);
      output[destination + 3] =
          _extractChannel(pixel, alphaMask, 255);
    }
  }
}

int _extractChannel(int pixel, int mask, int fallback) {
  if (mask == 0) {
    return fallback;
  }

  int shift = 0;

  while (((mask >> shift) & 1) == 0) {
    shift++;
  }

  final int maximum = mask >> shift;
  final int value = (pixel & mask) >> shift;

  return (value * 255 + maximum ~/ 2) ~/ maximum;
}

void _decodeBlocks(
  Uint8List data,
  int offset,
  Uint8List output,
  int width,
  int height,
  String format,
) {
  final int blocksWide = (width + 3) ~/ 4;
  final int blocksHigh = (height + 3) ~/ 4;

  final int blockSize = format == 'BC1' || format == 'BC4'
      ? 8
      : 16;

  final int required = blocksWide * blocksHigh * blockSize;

  if (offset + required > data.length) {
    throw const FormatException('DDS block data is incomplete.');
  }

  for (int by = 0; by < blocksHigh; by++) {
    for (int bx = 0; bx < blocksWide; bx++) {
      final int blockOffset =
          offset + (by * blocksWide + bx) * blockSize;

      switch (format) {
        case 'BC1':
          _decodeColorBlock(
            data,
            blockOffset,
            output,
            width,
            height,
            bx,
            by,
            forceFourColor: false,
          );
          break;

        case 'BC2':
          final Uint8List alpha =
              _decodeBc2Alpha(data, blockOffset);

          _decodeColorBlock(
            data,
            blockOffset + 8,
            output,
            width,
            height,
            bx,
            by,
            forceFourColor: true,
            alpha: alpha,
          );
          break;

        case 'BC3':
          final Uint8List alpha =
              _decodeAlphaBlock(data, blockOffset);

          _decodeColorBlock(
            data,
            blockOffset + 8,
            output,
            width,
            height,
            bx,
            by,
            forceFourColor: true,
            alpha: alpha,
          );
          break;

        case 'BC4':
          final Uint8List channel =
              _decodeAlphaBlock(data, blockOffset);

          _writeSingleChannelBlock(
            output,
            width,
            height,
            bx,
            by,
            channel,
          );
          break;

        case 'BC5':
          final Uint8List red =
              _decodeAlphaBlock(data, blockOffset);

          final Uint8List green =
              _decodeAlphaBlock(data, blockOffset + 8);

          _writeNormalBlock(
            output,
            width,
            height,
            bx,
            by,
            red,
            green,
          );
          break;
      }
    }
  }
}

List<int> _rgb565(int value) {
  final int r = (value >> 11) & 31;
  final int g = (value >> 5) & 63;
  final int b = value & 31;

  return [
    (r * 255 + 15) ~/ 31,
    (g * 255 + 31) ~/ 63,
    (b * 255 + 15) ~/ 31,
  ];
}

void _decodeColorBlock(
  Uint8List data,
  int offset,
  Uint8List output,
  int width,
  int height,
  int bx,
  int by, {
  required bool forceFourColor,
  Uint8List? alpha,
}) {
  final int c0 = data[offset] | (data[offset + 1] << 8);
  final int c1 = data[offset + 2] | (data[offset + 3] << 8);

  final List<int> color0 = _rgb565(c0);
  final List<int> color1 = _rgb565(c1);

  final List<List<int>> palette = [
    [color0[0], color0[1], color0[2], 255],
    [color1[0], color1[1], color1[2], 255],
    [0, 0, 0, 255],
    [0, 0, 0, 255],
  ];

  if (c0 > c1 || forceFourColor) {
    palette[2] = [
      (2 * color0[0] + color1[0]) ~/ 3,
      (2 * color0[1] + color1[1]) ~/ 3,
      (2 * color0[2] + color1[2]) ~/ 3,
      255,
    ];

    palette[3] = [
      (color0[0] + 2 * color1[0]) ~/ 3,
      (color0[1] + 2 * color1[1]) ~/ 3,
      (color0[2] + 2 * color1[2]) ~/ 3,
      255,
    ];
  } else {
    palette[2] = [
      (color0[0] + color1[0]) ~/ 2,
      (color0[1] + color1[1]) ~/ 2,
      (color0[2] + color1[2]) ~/ 2,
      255,
    ];

    palette[3] = [0, 0, 0, 0];
  }

  final int indices =
      data[offset + 4] |
      (data[offset + 5] << 8) |
      (data[offset + 6] << 16) |
      (data[offset + 7] << 24);

  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 4; x++) {
      final int pixel = y * 4 + x;
      final int colorIndex = (indices >> (pixel * 2)) & 3;

      final List<int> color = palette[colorIndex];

      final int px = bx * 4 + x;
      final int py = by * 4 + y;

      if (px >= width || py >= height) {
        continue;
      }

      final int destination = (py * width + px) * 4;

      output[destination] = color[0];
      output[destination + 1] = color[1];
      output[destination + 2] = color[2];
      output[destination + 3] = alpha?[pixel] ?? color[3];
    }
  }
}

Uint8List _decodeBc2Alpha(Uint8List data, int offset) {
  final Uint8List alpha = Uint8List(16);

  for (int i = 0; i < 16; i++) {
    final int packed = data[offset + (i ~/ 2)];

    final int nibble = i.isEven
        ? packed & 0x0F
        : packed >> 4;

    alpha[i] = nibble * 17;
  }

  return alpha;
}

Uint8List _decodeAlphaBlock(Uint8List data, int offset) {
  final int a0 = data[offset];
  final int a1 = data[offset + 1];

  final List<int> palette = List<int>.filled(8, 0);

  palette[0] = a0;
  palette[1] = a1;

  if (a0 > a1) {
    for (int i = 1; i <= 6; i++) {
      palette[i + 1] =
          ((7 - i) * a0 + i * a1) ~/ 7;
    }
  } else {
    for (int i = 1; i <= 4; i++) {
      palette[i + 1] =
          ((5 - i) * a0 + i * a1) ~/ 5;
    }

    palette[6] = 0;
    palette[7] = 255;
  }

  final Uint8List result = Uint8List(16);

  for (int i = 0; i < 16; i++) {
    final int bitOffset = i * 3;
    final int byteIndex = bitOffset ~/ 8;
    final int shift = bitOffset & 7;

    int packed = data[offset + 2 + byteIndex];

    if (shift > 5) {
      packed |= data[offset + 3 + byteIndex] << 8;
    }

    final int index = (packed >> shift) & 7;

    result[i] = palette[index];
  }

  return result;
}

void _writeSingleChannelBlock(
  Uint8List output,
  int width,
  int height,
  int bx,
  int by,
  Uint8List channel,
) {
  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 4; x++) {
      final int px = bx * 4 + x;
      final int py = by * 4 + y;

      if (px >= width || py >= height) {
        continue;
      }

      final int value = channel[y * 4 + x];
      final int destination = (py * width + px) * 4;

      output[destination] = value;
      output[destination + 1] = value;
      output[destination + 2] = value;
      output[destination + 3] = 255;
    }
  }
}

void _writeNormalBlock(
  Uint8List output,
  int width,
  int height,
  int bx,
  int by,
  Uint8List red,
  Uint8List green,
) {
  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 4; x++) {
      final int px = bx * 4 + x;
      final int py = by * 4 + y;

      if (px >= width || py >= height) {
        continue;
      }

      final int pixel = y * 4 + x;

      final double nx = red[pixel] / 127.5 - 1.0;
      final double ny = green[pixel] / 127.5 - 1.0;

      final double nz =
          (1.0 - nx * nx - ny * ny).clamp(0.0, 1.0);

      final int blue =
          ((nz.sqrt() * 0.5 + 0.5) * 255).round();

      final int destination = (py * width + px) * 4;

      output[destination] = red[pixel];
      output[destination + 1] = green[pixel];
      output[destination + 2] = blue;
      output[destination + 3] = 255;
    }
  }
}

extension on double {
  double sqrt() {
    // Avoid importing dart:math just for this operation.
    if (this <= 0) {
      return 0;
    }

    double result = this;
    double previous = 0;

    while (result != previous) {
      previous = result;
      result = (result + this / result) / 2;
    }

    return result;
  }
}
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glyphxtools/files/image/dds_decoder.dart';

import 'package:glyphxtools/files/meg/mega_file.dart';

class MegaDdsViewer extends StatefulWidget {
  const MegaDdsViewer({
    super.key,
    required this.file,
    this.backgroundColor = const Color(0xFF181818),
    this.showInfo = true,
  });

  final MegaFile file;
  final Color backgroundColor;
  final bool showInfo;

  @override
  State<MegaDdsViewer> createState() => _MegaDdsViewerState();
}

class _MegaDdsViewerState extends State<MegaDdsViewer> {
  ui.Image? _image;

  bool _loading = true;

  String? _error;
  String _format = '';

  @override
  void initState() {
    super.initState();
    _decodeFile();
  }

  @override
  void didUpdateWidget(covariant MegaDdsViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(widget.file, oldWidget.file)) {
      _image?.dispose();
      _image = null;
      _error = null;
      _loading = true;

      _decodeFile();
    }
  }

  Future<void> _decodeFile() async {
    try {
      if (!widget.file.path.toLowerCase().endsWith('.dds')) {
        throw const FormatException('This file is not a DDS texture.');
      }

      final Uint8List bytes = widget.file.data is Uint8List
          ? widget.file.data as Uint8List
          : Uint8List.fromList(widget.file.data);

      final DdsDecodedPixels decoded =
          await compute(decodeDdsPixels, bytes);

      final Completer<ui.Image> completer = Completer<ui.Image>();

      ui.decodeImageFromPixels(
        decoded.rgba,
        decoded.width,
        decoded.height,
        ui.PixelFormat.rgba8888,
        (ui.Image image) {
          completer.complete(image);
        },
      );

      final ui.Image image = await completer.future;

      if (!mounted) {
        image.dispose();
        return;
      }

      setState(() {
        _image = image;
        _format = decoded.format;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: const Center(
          child: Text(
            'Decoding DDS texture...',
            style: TextStyle(color: Color(0xFFFFFFFF)),
          ),
        ),
      );
    }

    if (_error != null) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFF7777),
              ),
            ),
          ),
        ),
      );
    }

    final ui.Image? image = _image;

    if (image == null) {
      return const SizedBox.shrink();
    }

    return ColoredBox(
      color: widget.backgroundColor,
      child: Column(
        children: [
          if (widget.showInfo)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.file.path.split(RegExp(r'[/\\]')).last,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${image.width} × ${image.height}  •  $_format',
                    style: const TextStyle(
                      color: Color(0xFFAAAAAA),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.1,
              maxScale: 8,
              child: Center(
                child: RawImage(
                  image: image,
                  width: image.width.toDouble(),
                  height: image.height.toDouble(),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
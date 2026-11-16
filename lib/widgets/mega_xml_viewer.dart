import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:glyphxtools/files/meg/mega_file.dart';
import 'package:material_ui/material_ui.dart';

class MegaXmlViewer extends StatefulWidget {
  const MegaXmlViewer({
    super.key,
    required this.file,
    this.backgroundColor = const Color(0xFF181818),
    this.showInfo = true,
  });

  final MegaFile file;
  final Color backgroundColor;
  final bool showInfo;

  @override
  State<MegaXmlViewer> createState() => _MegaXmlViewerState();
}

class _MegaXmlViewerState extends State<MegaXmlViewer> {
  late final ScrollController _verticalController;
  late final ScrollController _horizontalController;

  String _source = '';
  String? _error;

  int _lineCount = 0;

  @override
  void initState() {
    super.initState();

    _verticalController = ScrollController();
    _horizontalController = ScrollController();

    _loadFile();
  }

  @override
  void didUpdateWidget(covariant MegaXmlViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.file, widget.file)) {
      _loadFile();
    }
  }

  void _loadFile() {
    try {
      if (!widget.file.path.toLowerCase().endsWith('.xml')) {
        throw const FormatException('This file is not an XML file.');
      }

      String source = utf8.decode(widget.file.data, allowMalformed: true);

      // Remove UTF-8 BOM if present.
      if (source.startsWith('\uFEFF')) {
        source = source.substring(1);
      }

      setState(() {
        _source = source;
        _lineCount = source.isEmpty ? 0 : source.split('\n').length;
        _error = null;
      });

      if (_verticalController.hasClients) {
        _verticalController.jumpTo(0);
      }

      if (_horizontalController.hasClients) {
        _horizontalController.jumpTo(0);
      }
    } catch (error) {
      setState(() {
        _source = '';
        _lineCount = 0;
        _error = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String fileName = widget.file.path
        .replaceAll('\\', '/')
        .split('/')
        .last;

    return ColoredBox(
      color: widget.backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showInfo)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.code, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'XML • $_lineCount lines • '
                          '${widget.file.data.length} bytes',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy XML',
                    icon: const Icon(Icons.copy),
                    onPressed: _source.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: _source));

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('XML copied to clipboard.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText(
                        'Could not load XML:\n$_error',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return Scrollbar(
                        controller: _verticalController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _verticalController,
                          child: Scrollbar(
                            controller: _horizontalController,
                            thumbVisibility: true,
                            notificationPredicate: (notification) {
                              return notification.metrics.axis ==
                                  Axis.horizontal;
                            },
                            child: SingleChildScrollView(
                              controller: _horizontalController,
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: SelectionArea(
                                  child: HighlightView(
                                    _source,
                                    language: 'xml',
                                    theme: atomOneDarkTheme,
                                    padding: const EdgeInsets.all(16),
                                    textStyle: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

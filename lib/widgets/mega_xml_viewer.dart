import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:glyphxtools/files/meg/mega_file.dart';
import 'package:highlight/highlight.dart' show highlight, Node, Result;
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
  static const TextStyle _baseStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.5,
    color: Color(0xFFABB2BF),
  );

  static const TextStyle _foldPlaceholderStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.5,
    color: Color(0xFF6B7280),
    fontStyle: FontStyle.italic,
  );

  static const double _lineHeight = 19.5;
  static const double _gutterWidth = 54;
  static const double _characterWidth = 8.2;
  static const Color _matchColor = Color(0x665C5128);
  static const Color _activeMatchColor = Color(0xCC9A7229);

  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _selectedText = ValueNotifier<String>('');

  Timer? _searchDebounce;

  String _source = '';
  String _lowerSource = '';
  String? _error;

  int _lineCount = 0;
  int _maxLineLength = 0;
  int _searchLength = 0;
  int _currentMatchIndex = -1;
  String _appliedSearchQuery = '';

  List<_SyntaxSegment> _syntaxSegments = [];
  List<int> _lineStarts = [0];
  List<int> _lineEnds = [0];
  List<int> _visibleLines = [];
  List<int> _searchMatches = [];

  Map<int, _XmlFoldRegion> _foldRegions = {};
  Map<int, int> _visibleIndexBySourceLine = {};
  Set<int> _collapsedLines = {};

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void didUpdateWidget(covariant MegaXmlViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.file, widget.file)) {
      _loadFile();
    }
  }

  // ---------------------------------------------------------------------------
  // Syntax highlighting: parse once, retain only source-offset/style segments.
  // ---------------------------------------------------------------------------

  List<_SyntaxSegment> _buildSyntaxSegments(String source) {
    final Result result = highlight.parse(source, language: 'xml');
    final List<_SyntaxSegment> segments = [];
    final List<int> offset = [0];

    for (final Node node in result.nodes ?? <Node>[]) {
      _collectSyntaxNode(node, _baseStyle, segments, offset, source.length);
    }

    if (offset[0] < source.length) {
      segments.add(_SyntaxSegment(offset[0], source.length, _baseStyle));
    }

    return segments;
  }

  void _collectSyntaxNode(
    Node node,
    TextStyle? inheritedStyle,
    List<_SyntaxSegment> segments,
    List<int> offset,
    int sourceLength,
  ) {
    final TextStyle? tokenStyle = node.className == null
        ? null
        : atomOneDarkTheme[node.className!];
    final TextStyle? effectiveStyle = tokenStyle ?? inheritedStyle;

    if (node.value != null) {
      final int remaining = sourceLength - offset[0];
      final int length = math.min(node.value!.length, remaining).toInt();
      if (length > 0) {
        final int nextOffset = offset[0] + length;
        final _SyntaxSegment? previous =
            segments.isEmpty ? null : segments.last;

        // Merge adjacent tokens with identical styling to keep the segment
        // index compact, especially for large XML documents.
        if (previous != null &&
            previous.end == offset[0] &&
            previous.style == effectiveStyle) {
          segments[segments.length - 1] = _SyntaxSegment(
            previous.start,
            nextOffset,
            effectiveStyle,
          );
        } else {
          segments.add(
            _SyntaxSegment(offset[0], nextOffset, effectiveStyle),
          );
        }

        offset[0] = nextOffset;
      }
      return;
    }

    for (final Node child in node.children ?? <Node>[]) {
      _collectSyntaxNode(
        child,
        effectiveStyle,
        segments,
        offset,
        sourceLength,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Line indexing and XML folding.
  // ---------------------------------------------------------------------------

  void _buildLineIndex(
    String source,
    List<int> starts,
    List<int> ends,
  ) {
    starts.add(0);
    for (int i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 10) {
        ends.add(i);
        starts.add(i + 1);
      }
    }
    ends.add(source.length);

    // Exclude CR from CRLF line endings while preserving it in _source.
    for (int i = 0; i < ends.length; i++) {
      if (ends[i] > starts[i] && source.codeUnitAt(ends[i] - 1) == 13) {
        ends[i]--;
      }
    }
  }

  int _lineForOffsetIn(List<int> starts, int offset) {
    int low = 0;
    int high = starts.length - 1;
    int result = 0;

    while (low <= high) {
      final int middle = (low + high) >> 1;
      if (starts[middle] <= offset) {
        result = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return result;
  }

  int _lineForOffset(int offset) => _lineForOffsetIn(_lineStarts, offset);

  Map<int, _XmlFoldRegion> _parseFoldRegions(
    String source,
    List<int> lineStarts,
  ) {
    final Map<int, _XmlFoldRegion> regions = {};
    final List<_OpenXmlElement> stack = [];
    int index = 0;

    while (index < source.length) {
      if (source.startsWith('<!--', index)) {
        final int end = source.indexOf('-->', index + 4);
        index = end == -1 ? source.length : end + 3;
        continue;
      }
      if (source.startsWith('<![CDATA[', index)) {
        final int end = source.indexOf(']]>', index + 9);
        index = end == -1 ? source.length : end + 3;
        continue;
      }
      if (source.startsWith('<?', index)) {
        final int end = source.indexOf('?>', index + 2);
        index = end == -1 ? source.length : end + 2;
        continue;
      }
      if (source.startsWith('<!', index)) {
        final int end = _findMarkupEnd(source, index, declaration: true);
        index = end == -1 ? source.length : end + 1;
        continue;
      }
      if (source.codeUnitAt(index) != 60) {
        index++;
        continue;
      }

      final int tagEnd = _findMarkupEnd(source, index);
      if (tagEnd == -1) {
        index++;
        continue;
      }

      int nameStart = index + 1;
      bool closing = false;
      if (nameStart < source.length && source.codeUnitAt(nameStart) == 47) {
        closing = true;
        nameStart++;
      }
      while (nameStart < tagEnd && _isWhitespace(source.codeUnitAt(nameStart))) {
        nameStart++;
      }

      int nameEnd = nameStart;
      while (nameEnd < tagEnd) {
        final int c = source.codeUnitAt(nameEnd);
        if (_isWhitespace(c) || c == 47 || c == 62 || c == 63) break;
        nameEnd++;
      }
      if (nameEnd == nameStart) {
        index = tagEnd + 1;
        continue;
      }

      final String tagName = source.substring(nameStart, nameEnd);
      if (closing) {
        int matchingIndex = -1;
        for (int i = stack.length - 1; i >= 0; i--) {
          if (stack[i].name == tagName) {
            matchingIndex = i;
            break;
          }
        }
        if (matchingIndex != -1) {
          final _OpenXmlElement opened = stack[matchingIndex];
          stack.removeRange(matchingIndex, stack.length);
          final int startLine = _lineForOffsetIn(lineStarts, opened.offset);
          final int endLine = _lineForOffsetIn(lineStarts, index);
          if (endLine > startLine) {
            final _XmlFoldRegion region = _XmlFoldRegion(
              startLine: startLine,
              endLine: endLine,
              tagName: tagName,
            );
            final _XmlFoldRegion? previous = regions[startLine];
            // If several elements start on one line, retain the outer range.
            if (previous == null || region.endLine > previous.endLine) {
              regions[startLine] = region;
            }
          }
        }
      } else {
        int last = tagEnd - 1;
        while (last > nameEnd && _isWhitespace(source.codeUnitAt(last))) {
          last--;
        }
        if (source.codeUnitAt(last) != 47) {
          stack.add(_OpenXmlElement(tagName, index));
        }
      }
      index = tagEnd + 1;
    }

    return regions;
  }

  int _findMarkupEnd(
    String source,
    int start, {
    bool declaration = false,
  }) {
    int bracketDepth = 0;
    String? quote;

    for (int i = start + 1; i < source.length; i++) {
      final String character = source[i];
      if (quote != null) {
        if (character == quote) quote = null;
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
        continue;
      }
      if (declaration) {
        if (character == '[') bracketDepth++;
        if (character == ']' && bracketDepth > 0) bracketDepth--;
      }
      if (character == '>' && bracketDepth == 0) return i;
    }
    return -1;
  }

  bool _isWhitespace(int codeUnit) =>
      codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13;

  void _rebuildVisibleLines() {
    final List<int> lines = [];
    final Map<int, int> indexByLine = {};

    int line = 0;
    while (line < _lineStarts.length) {
      indexByLine[line] = lines.length;
      lines.add(line);

      final _XmlFoldRegion? region = _foldRegions[line];
      if (region != null && _collapsedLines.contains(line)) {
        line = region.endLine + 1;
      } else {
        line++;
      }
    }

    _visibleLines = lines;
    _visibleIndexBySourceLine = indexByLine;
  }

  void _toggleFold(int line) {
    if (!_foldRegions.containsKey(line)) return;
    setState(() {
      if (!_collapsedLines.add(line)) _collapsedLines.remove(line);
      _selectedText.value = '';
      _rebuildVisibleLines();
    });
  }

  void _foldAll() {
    if (_collapsedLines.length == _foldRegions.length) return;
    setState(() {
      _collapsedLines = _foldRegions.keys.toSet();
      _selectedText.value = '';
      _rebuildVisibleLines();
    });
  }

  void _unfoldAll() {
    if (_collapsedLines.isEmpty) return;
    setState(() {
      _collapsedLines.clear();
      _selectedText.value = '';
      _rebuildVisibleLines();
    });
  }

  bool _expandCollapsedForLine(int line) {
    bool changed = false;
    final List<int> collapsed = _collapsedLines.toList(growable: false);
    for (final int startLine in collapsed) {
      final _XmlFoldRegion? region = _foldRegions[startLine];
      if (region != null && line > startLine && line <= region.endLine) {
        _collapsedLines.remove(startLine);
        changed = true;
      }
    }
    return changed;
  }

  // ---------------------------------------------------------------------------
  // Search. Results are source offsets; no whole-document TextSpan rebuild.
  // ---------------------------------------------------------------------------

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) _performSearch(query);
    });
  }

  void _performSearch(String query) {
    final String needle = query.toLowerCase();
    final List<int> matches = [];

    if (needle.isNotEmpty) {
      int offset = 0;
      while (offset <= _lowerSource.length - needle.length) {
        final int index = _lowerSource.indexOf(needle, offset);
        if (index == -1) break;
        matches.add(index);
        offset = index + needle.length;
      }
    }

    _searchMatches = matches;
    _searchLength = needle.length;
    _currentMatchIndex = matches.isEmpty ? -1 : 0;
    _appliedSearchQuery = query;

    bool changed = false;
    if (matches.isNotEmpty) {
      changed = _expandCollapsedForLine(_lineForOffset(matches.first));
    }

    if (changed) _rebuildVisibleLines();
    setState(() {});

    if (matches.isNotEmpty) _scrollToCurrentMatch();
  }

  void _navigateMatch(int direction) {
    _searchDebounce?.cancel();
    if (_searchController.text != _appliedSearchQuery) {
      _performSearch(_searchController.text);
      return;
    }
    if (_searchMatches.isEmpty) return;

    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex + direction) % _searchMatches.length;
      if (_currentMatchIndex < 0) {
        _currentMatchIndex += _searchMatches.length;
      }

      final int line = _lineForOffset(
        _searchMatches[_currentMatchIndex],
      );
      if (_expandCollapsedForLine(line)) _rebuildVisibleLines();
    });
    _scrollToCurrentMatch();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _performSearch('');
  }

  void _scrollToCurrentMatch() {
    if (_currentMatchIndex < 0 || _searchMatches.isEmpty) return;

    final int sourceLine = _lineForOffset(
      _searchMatches[_currentMatchIndex],
    );
    final int? visibleIndex = _visibleIndexBySourceLine[sourceLine];
    if (visibleIndex == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalController.hasClients) return;
      final ScrollPosition position = _verticalController.position;
      final double target =
          (visibleIndex * _lineHeight - position.viewportDimension * 0.35)
              .clamp(0.0, position.maxScrollExtent)
              .toDouble();
      _verticalController.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  int _firstSegmentEndingAfter(int offset) {
    int low = 0;
    int high = _syntaxSegments.length;
    while (low < high) {
      final int middle = (low + high) >> 1;
      if (_syntaxSegments[middle].end <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _firstMatchEndingAfter(int offset) {
    int low = 0;
    int high = _searchMatches.length;
    while (low < high) {
      final int middle = (low + high) >> 1;
      if (_searchMatches[middle] + _searchLength <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  // ---------------------------------------------------------------------------
  // Build one visible line only. ListView.builder virtualizes the document.
  // ---------------------------------------------------------------------------

  TextSpan _buildLineSpan(int line) {
    final int start = _lineStarts[line];
    final int end = _lineEnds[line];
    final List<InlineSpan> spans = [];

    int position = start;
    int segmentIndex = _firstSegmentEndingAfter(start);
    int matchIndex = _firstMatchEndingAfter(start);

    while (position < end) {
      while (segmentIndex < _syntaxSegments.length &&
          _syntaxSegments[segmentIndex].end <= position) {
        segmentIndex++;
      }

      final _SyntaxSegment? segment =
          segmentIndex < _syntaxSegments.length
              ? _syntaxSegments[segmentIndex]
              : null;

      TextStyle? syntaxStyle = _baseStyle;
      int segmentEnd = end;

      if (segment != null) {
        if (segment.start > position) {
          segmentEnd = math.min(end, segment.start).toInt();
        } else {
          syntaxStyle = segment.style;
          segmentEnd = math.min(end, segment.end).toInt();
        }
      }

      if (segmentEnd <= position) break;

      while (position < segmentEnd) {
        while (matchIndex < _searchMatches.length &&
            _searchMatches[matchIndex] + _searchLength <= position) {
          matchIndex++;
        }

        final int pieceEnd;
        TextStyle? pieceStyle = syntaxStyle;

        if (matchIndex < _searchMatches.length &&
            _searchMatches[matchIndex] <= position &&
            _searchMatches[matchIndex] + _searchLength > position) {
          pieceEnd = math.min(
            segmentEnd,
            _searchMatches[matchIndex] + _searchLength,
          ).toInt();
          pieceStyle = (syntaxStyle ?? _baseStyle).copyWith(
            backgroundColor: matchIndex == _currentMatchIndex
                ? _activeMatchColor
                : _matchColor,
          );
        } else if (matchIndex < _searchMatches.length &&
            _searchMatches[matchIndex] < segmentEnd) {
          pieceEnd = _searchMatches[matchIndex];
        } else {
          pieceEnd = segmentEnd;
        }

        if (pieceEnd <= position) break;

        spans.add(
          TextSpan(
            text: _source.substring(position, pieceEnd),
            style: pieceStyle,
          ),
        );
        position = pieceEnd;
      }
    }

    final _XmlFoldRegion? region = _foldRegions[line];
    if (region != null && _collapsedLines.contains(line)) {
      final int hiddenLines = region.endLine - line;
      spans.add(
        TextSpan(
          text: '  … </${region.tagName}> ($hiddenLines lines)',
          style: _foldPlaceholderStyle,
        ),
      );
    }

    return TextSpan(style: _baseStyle, children: spans);
  }

  Widget _buildLine(int visibleIndex) {
    final int sourceLine = _visibleLines[visibleIndex];
    final _XmlFoldRegion? region = _foldRegions[sourceLine];
    final bool collapsed = _collapsedLines.contains(sourceLine);

    return SizedBox(
      height: _lineHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SelectionContainer.disabled(
            child: SizedBox(
              width: _gutterWidth,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: region == null
                        ? const SizedBox.shrink()
                        : Tooltip(
                            message: collapsed ? 'Unfold section' : 'Fold section',
                            child: InkWell(
                              onTap: () => _toggleFold(sourceLine),
                              child: SizedBox(
                                width: 20,
                                height: _lineHeight,
                                child: Icon(
                                  collapsed
                                      ? Icons.chevron_right
                                      : Icons.expand_more,
                                  size: 16,
                                  color: const Color(0xFF858C98),
                                ),
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: Text(
                      '${sourceLine + 1}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF626A78),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              _buildLineSpan(sourceLine),
              softWrap: false,
              maxLines: 1,
              style: _baseStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double documentWidth = math.max(
          constraints.maxWidth,
          _gutterWidth + _maxLineLength * _characterWidth + 16,
        ).toDouble();

        return Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: documentWidth,
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: _verticalController,
                thumbVisibility: true,
                child: SelectionArea(
                  onSelectionChanged: (content) {
                    final String selected = content?.plainText ?? '';
                    if (_selectedText.value != selected) {
                      _selectedText.value = selected;
                    }
                  },
                  child: ListView.builder(
                    controller: _verticalController,
                    itemCount: _visibleLines.length,
                    itemExtent: _lineHeight,
                    itemBuilder: (context, index) => _buildLine(index),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // File loading
  // ---------------------------------------------------------------------------

  void _loadFile() {
    _searchDebounce?.cancel();

    try {
      if (!widget.file.path.toLowerCase().endsWith('.xml')) {
        throw const FormatException('This file is not an XML file.');
      }

      String source = utf8.decode(
        widget.file.data,
        allowMalformed: true,
      );
      if (source.startsWith('\uFEFF')) {
        source = source.substring(1);
      }

      final List<_SyntaxSegment> syntaxSegments =
          _buildSyntaxSegments(source);
      final List<int> lineStarts = [];
      final List<int> lineEnds = [];
      _buildLineIndex(source, lineStarts, lineEnds);

      final Map<int, _XmlFoldRegion> foldRegions =
          _parseFoldRegions(source, lineStarts);

      int maxLineLength = 0;
      for (int i = 0; i < lineStarts.length; i++) {
        maxLineLength = math.max(
          maxLineLength,
          lineEnds[i] - lineStarts[i],
        ).toInt();
      }

      _searchController.clear();
      _selectedText.value = '';

      setState(() {
        _source = source;
        _lowerSource = source.toLowerCase();
        _syntaxSegments = syntaxSegments;
        _lineStarts = lineStarts;
        _lineEnds = lineEnds;
        _lineCount = lineStarts.length;
        _maxLineLength = maxLineLength;

        _foldRegions = foldRegions;
        _collapsedLines.clear();

        _searchMatches = [];
        _searchLength = 0;
        _currentMatchIndex = -1;
        _appliedSearchQuery = '';
        _error = null;

        _rebuildVisibleLines();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_verticalController.hasClients) {
          _verticalController.jumpTo(0);
        }
        if (_horizontalController.hasClients) {
          _horizontalController.jumpTo(0);
        }
      });
    } catch (error) {
      setState(() {
        _source = '';
        _lowerSource = '';
        _syntaxSegments = [];
        _lineStarts = [0];
        _lineEnds = [0];
        _lineCount = 0;
        _maxLineLength = 0;
        _foldRegions = {};
        _collapsedLines = {};
        _visibleLines = [];
        _visibleIndexBySourceLine = {};
        _searchMatches = [];
        _searchLength = 0;
        _currentMatchIndex = -1;
        _error = error.toString();
        _selectedText.value = '';
        _searchController.clear();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Clipboard and search toolbar.
  // ---------------------------------------------------------------------------

  Future<void> _copyText(String text, String message) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildToolbar() {
    final bool hasMatches = _searchMatches.isNotEmpty;
    final bool hasFolds = _foldRegions.isNotEmpty;
    final bool allCollapsed =
        hasFolds && _collapsedLines.length == _foldRegions.length;

    final String matchLabel = _searchController.text.isEmpty
        ? 'Search XML'
        : _searchController.text != _appliedSearchQuery
            ? 'Searching…'
            : hasMatches
                ? '${_currentMatchIndex + 1} / ${_searchMatches.length}'
                : 'No matches';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _navigateMatch(1),
                  decoration: InputDecoration(
                    hintText: 'Search XML...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                matchLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IconButton(
                tooltip: 'Previous match',
                onPressed: hasMatches ? () => _navigateMatch(-1) : null,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: 'Next match',
                onPressed: hasMatches ? () => _navigateMatch(1) : null,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: !hasFolds || allCollapsed ? null : _foldAll,
                icon: const Icon(Icons.unfold_less),
                label: const Text('Fold All'),
              ),
              TextButton.icon(
                onPressed: _collapsedLines.isEmpty ? null : _unfoldAll,
                icon: const Icon(Icons.unfold_more),
                label: const Text('Unfold All'),
              ),
            ],
          ),
        ],
      ),
    );
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
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
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
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'XML • $_lineCount lines • '
                          '${widget.file.data.length} bytes • '
                          '${_foldRegions.length} foldable sections',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: _selectedText,
                    builder: (context, selected, child) {
                      return IconButton(
                        tooltip: 'Copy selection',
                        onPressed: selected.isEmpty
                            ? null
                            : () => _copyText(
                                  selected,
                                  'Selected XML section copied.',
                                ),
                        icon: const Icon(Icons.content_copy),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Copy entire XML',
                    onPressed: _source.isEmpty
                        ? null
                        : () => _copyText(
                              _source,
                              'XML file copied.',
                            ),
                    icon: const Icon(Icons.copy_all),
                  ),
                ],
              ),
            ),
          _buildToolbar(),
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
                : _buildEditor(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _selectedText.dispose();
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }
}

// =============================================================================
// Internal data structures.
// =============================================================================

class _SyntaxSegment {
  const _SyntaxSegment(this.start, this.end, this.style);

  final int start;
  final int end;
  final TextStyle? style;
}

class _OpenXmlElement {
  const _OpenXmlElement(this.name, this.offset);

  final String name;
  final int offset;
}

class _XmlFoldRegion {
  const _XmlFoldRegion({
    required this.startLine,
    required this.endLine,
    required this.tagName,
  });

  final int startLine;
  final int endLine;
  final String tagName;
}

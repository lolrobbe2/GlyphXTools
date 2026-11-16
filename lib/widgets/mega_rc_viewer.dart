import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:glyphxtools/files/meg/mega_file.dart';
import 'package:material_ui/material_ui.dart';

class MegaRcViewer extends StatefulWidget {
  const MegaRcViewer({
    super.key,
    required this.file,
    this.backgroundColor = const Color(0xFF181818),
    this.showInfo = true,
  });

  final MegaFile file;
  final Color backgroundColor;
  final bool showInfo;

  @override
  State<MegaRcViewer> createState() => _MegaRcViewerState();
}

class _MegaRcViewerState extends State<MegaRcViewer> {
  static const TextStyle _baseStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.5,
    color: Color(0xFFABB2BF),
  );

  static const TextStyle _foldStyle = TextStyle(
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

  static const TextStyle _keywordStyle = TextStyle(color: Color(0xFFC678DD));

  static const TextStyle _resourceStyle = TextStyle(color: Color(0xFFE5C07B));

  static const TextStyle _constantStyle = TextStyle(color: Color(0xFF56B6C2));

  static const TextStyle _stringStyle = TextStyle(color: Color(0xFF98C379));

  static const TextStyle _numberStyle = TextStyle(color: Color(0xFFD19A66));

  static const TextStyle _commentStyle = TextStyle(
    color: Color(0xFF5C6370),
    fontStyle: FontStyle.italic,
  );

  static const TextStyle _preprocessorStyle = TextStyle(
    color: Color(0xFFE06C75),
  );

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

  List<_RcSegment> _segments = [];
  List<int> _lineStarts = [0];
  List<int> _lineEnds = [0];
  List<int> _visibleLines = [];
  List<int> _searchMatches = [];

  Map<int, _RcFoldRegion> _foldRegions = {};
  Map<int, int> _visibleIndexByLine = {};
  Set<int> _collapsedLines = {};

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void didUpdateWidget(covariant MegaRcViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.file, widget.file)) {
      _loadFile();
    }
  }

  // ---------------------------------------------------------------------------
  // RC syntax highlighting.
  // ---------------------------------------------------------------------------

  List<_RcSegment> _buildSyntaxSegments(String source) {
    final List<_RcSegment> segments = [];

    final RegExp tokenPattern = RegExp(
      r"""//[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|#[^\r\n]*|\b0[xX][0-9a-fA-F]+\b|\b\d+\b|\b[A-Za-z_][A-Za-z0-9_]*\b""",
    );

    final Set<String> keywords = {
      'BEGIN',
      'END',
      'DIALOG',
      'DIALOGEX',
      'MENU',
      'MENUEX',
      'STRINGTABLE',
      'ACCELERATORS',
      'VERSIONINFO',
      'RCDATA',
      'HTML',
      'FONT',
      'ICON',
      'BITMAP',
      'CURSOR',
      'ANICURSOR',
      'ANIICON',
      'TYPELIB',
      'MESSAGETABLE',
      'TOOLBAR',
      'DLGINCLUDE',
      'AUTO3STATE',
      'AUTOCHECKBOX',
      'AUTORADIOBUTTON',
      'CHECKBOX',
      'COMBOBOX',
      'CTEXT',
      'DEFPUSHBUTTON',
      'EDITTEXT',
      'GROUPBOX',
      'ICON',
      'LISTBOX',
      'LTEXT',
      'PUSHBUTTON',
      'RADIOBUTTON',
      'RTEXT',
      'SCROLLBAR',
      'STATE3',
      'CAPTION',
      'CHARACTERISTICS',
      'CLASS',
      'EXSTYLE',
      'LANGUAGE',
      'MENUITEM',
      'POPUP',
      'SEPARATOR',
      'STYLE',
      'VERSION',
      'FILEVERSION',
      'PRODUCTVERSION',
      'FILEDESCRIPTION',
      'FILEVERSION',
      'PRODUCTNAME',
      'BLOCK',
      'VALUE',
    };

    final Set<String> resourceTypes = {
      'DIALOG',
      'DIALOGEX',
      'MENU',
      'MENUEX',
      'STRINGTABLE',
      'ACCELERATORS',
      'VERSIONINFO',
      'RCDATA',
      'HTML',
      'ICON',
      'BITMAP',
      'CURSOR',
      'ANICURSOR',
      'ANIICON',
      'TYPELIB',
      'MESSAGETABLE',
      'TOOLBAR',
    };

    final Set<String> constants = {
      'WS_VISIBLE',
      'WS_CHILD',
      'WS_POPUP',
      'WS_CAPTION',
      'WS_SYSMENU',
      'WS_THICKFRAME',
      'WS_MINIMIZEBOX',
      'WS_MAXIMIZEBOX',
      'WS_TABSTOP',
      'WS_DISABLED',
      'DS_SETFONT',
      'DS_MODALFRAME',
      'DS_CENTER',
      'DS_CONTROL',
      'ES_LEFT',
      'ES_RIGHT',
      'ES_CENTER',
      'BS_PUSHBUTTON',
      'BS_DEFPUSHBUTTON',
      'BS_AUTOCHECKBOX',
      'BS_AUTORADIOBUTTON',
      'SS_LEFT',
      'SS_CENTER',
      'SS_RIGHT',
      'LBS_NOTIFY',
      'CBS_DROPDOWN',
      'WS_EX_CLIENTEDGE',
      'WS_EX_STATICEDGE',
      'IDOK',
      'IDCANCEL',
      'IDABORT',
      'IDRETRY',
      'IDIGNORE',
      'IDYES',
      'IDNO',
      'IDC_STATIC',
      'TRUE',
      'FALSE',
    };

    for (final RegExpMatch match in tokenPattern.allMatches(source)) {
      final String token = match.group(0)!;
      final String upper = token.toUpperCase();

      TextStyle? style;

      if (token.startsWith('//') || token.startsWith('/*')) {
        style = _commentStyle;
      } else if (token.startsWith('"') || token.startsWith("'")) {
        style = _stringStyle;
      } else if (token.startsWith('#')) {
        style = _preprocessorStyle;
      } else if (token.isNotEmpty &&
          token.codeUnitAt(0) >= 48 &&
          token.codeUnitAt(0) <= 57) {
        style = _numberStyle;
      } else if (resourceTypes.contains(upper)) {
        style = _resourceStyle;
      } else if (keywords.contains(upper)) {
        style = _keywordStyle;
      } else if (constants.contains(upper) ||
          upper.startsWith('WS_') ||
          upper.startsWith('DS_') ||
          upper.startsWith('ES_') ||
          upper.startsWith('BS_') ||
          upper.startsWith('SS_') ||
          upper.startsWith('CBS_') ||
          upper.startsWith('LBS_')) {
        style = _constantStyle;
      }

      if (style == null) continue;

      segments.add(_RcSegment(match.start, match.end, style));
    }

    return segments;
  }

  // ---------------------------------------------------------------------------
  // Line indexing.
  // ---------------------------------------------------------------------------

  void _buildLineIndex(String source, List<int> starts, List<int> ends) {
    starts.add(0);

    for (int i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 10) {
        ends.add(i);
        starts.add(i + 1);
      }
    }

    ends.add(source.length);

    for (int i = 0; i < ends.length; i++) {
      if (ends[i] > starts[i] && source.codeUnitAt(ends[i] - 1) == 13) {
        ends[i]--;
      }
    }
  }

  int _lineForOffset(int offset) {
    int low = 0;
    int high = _lineStarts.length - 1;
    int result = 0;

    while (low <= high) {
      final int middle = (low + high) >> 1;

      if (_lineStarts[middle] <= offset) {
        result = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // RC folding.
  //
  // Only BEGIN/END tokens outside strings and comments are considered.
  // Nested BEGIN/END blocks are supported.
  // ---------------------------------------------------------------------------

  Map<int, _RcFoldRegion> _parseFoldRegions(
    String source,
    List<int> lineStarts,
    List<int> lineEnds,
  ) {
    final Map<int, _RcFoldRegion> regions = {};
    final List<int> stack = [];

    final RegExp tokenPattern = RegExp(
      r"""//[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|#[^\r\n]*|\bBEGIN\b|\bEND\b""",
      caseSensitive: false,
    );

    final RegExp resourceHeaderPattern = RegExp(
      r"""^\s*(?:(?:"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z0-9_]*|\d+)\s+(?:DIALOGEX?|MENUEX?|MENU|ACCELERATORS|VERSIONINFO|RCDATA|HTML|FONT|ICON|BITMAP|CURSOR|ANICURSOR|ANIICON|TYPELIB|MESSAGETABLE|TOOLBAR|DLGINCLUDE)\b|STRINGTABLE\b|POPUP\b|BLOCK\b)""",
      caseSensitive: false,
    );

    int lineForOffset(int offset) {
      int low = 0;
      int high = lineStarts.length;

      while (low < high) {
        final int middle = low + ((high - low) >> 1);

        if (lineStarts[middle] <= offset) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }

      return low - 1;
    }

    int declarationLineForBegin(int beginLine, int beginOffset) {
      final String prefix = source
          .substring(lineStarts[beginLine], beginOffset)
          .trim();

      // BEGIN is on the same line as its declaration.
      if (prefix.isNotEmpty) {
        return beginLine;
      }

      // Find the resource declaration preceding BEGIN.
      for (int line = beginLine - 1; line >= 0; line--) {
        final String text = source
            .substring(lineStarts[line], lineEnds[line])
            .trim();

        if (text.isEmpty) {
          break;
        }

        if (text.startsWith('#') ||
            text.startsWith('//') ||
            text.startsWith('/*') ||
            text.startsWith('*')) {
          continue;
        }

        if (resourceHeaderPattern.hasMatch(text)) {
          return line;
        }
      }

      // Fallback for unusual RC syntax.
      return beginLine;
    }

    for (final RegExpMatch match in tokenPattern.allMatches(source)) {
      final String token = match.group(0)!;

      // Ignore comments, strings and preprocessor directives.
      if (token.startsWith('//') ||
          token.startsWith('/*') ||
          token.startsWith('"') ||
          token.startsWith("'") ||
          token.startsWith('#')) {
        continue;
      }

      final int line = lineForOffset(match.start);

      if (token.toUpperCase() == 'BEGIN') {
        stack.add(declarationLineForBegin(line, match.start));
      } else if (token.toUpperCase() == 'END' && stack.isNotEmpty) {
        final int startLine = stack.removeLast();

        if (line > startLine) {
          regions[startLine] = _RcFoldRegion(
            startLine: startLine,
            endLine: line,
          );
        }
      }
    }

    return regions;
  }

  void _rebuildVisibleLines() {
    final List<int> lines = [];
    final Map<int, int> indexByLine = {};

    int line = 0;

    while (line < _lineStarts.length) {
      indexByLine[line] = lines.length;
      lines.add(line);

      final _RcFoldRegion? region = _foldRegions[line];

      if (region != null && _collapsedLines.contains(line)) {
        line = region.endLine + 1;
      } else {
        line++;
      }
    }

    _visibleLines = lines;
    _visibleIndexByLine = indexByLine;
  }

  void _toggleFold(int line) {
    if (!_foldRegions.containsKey(line)) return;

    setState(() {
      if (!_collapsedLines.add(line)) {
        _collapsedLines.remove(line);
      }

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
      final _RcFoldRegion? region = _foldRegions[startLine];

      if (region != null && line > startLine && line <= region.endLine) {
        _collapsedLines.remove(startLine);
        changed = true;
      }
    }

    return changed;
  }

  // ---------------------------------------------------------------------------
  // Search.
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

    if (matches.isNotEmpty) {
      _scrollToCurrentMatch();
    }
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

      final int line = _lineForOffset(_searchMatches[_currentMatchIndex]);

      if (_expandCollapsedForLine(line)) {
        _rebuildVisibleLines();
      }
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

    final int sourceLine = _lineForOffset(_searchMatches[_currentMatchIndex]);

    final int? visibleIndex = _visibleIndexByLine[sourceLine];

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

  // ---------------------------------------------------------------------------
  // Efficient line rendering.
  // ---------------------------------------------------------------------------

  int _firstSegmentEndingAfter(int offset) {
    int low = 0;
    int high = _segments.length;

    while (low < high) {
      final int middle = (low + high) >> 1;

      if (_segments[middle].end <= offset) {
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

  TextSpan _buildLineSpan(int line) {
    final int start = _lineStarts[line];
    final int end = _lineEnds[line];

    final List<InlineSpan> spans = [];

    int position = start;
    int segmentIndex = _firstSegmentEndingAfter(start);
    int matchIndex = _firstMatchEndingAfter(start);

    while (position < end) {
      while (segmentIndex < _segments.length &&
          _segments[segmentIndex].end <= position) {
        segmentIndex++;
      }

      final _RcSegment? segment = segmentIndex < _segments.length
          ? _segments[segmentIndex]
          : null;

      TextStyle syntaxStyle = _baseStyle;
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

        int pieceEnd = segmentEnd;
        TextStyle pieceStyle = syntaxStyle;

        if (matchIndex < _searchMatches.length &&
            _searchMatches[matchIndex] <= position &&
            _searchMatches[matchIndex] + _searchLength > position) {
          pieceEnd = math
              .min(segmentEnd, _searchMatches[matchIndex] + _searchLength)
              .toInt();

          pieceStyle = syntaxStyle.copyWith(
            backgroundColor: matchIndex == _currentMatchIndex
                ? _activeMatchColor
                : _matchColor,
          );
        } else if (matchIndex < _searchMatches.length &&
            _searchMatches[matchIndex] < segmentEnd) {
          pieceEnd = _searchMatches[matchIndex];
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

    final _RcFoldRegion? region = _foldRegions[line];

    if (region != null && _collapsedLines.contains(line)) {
      final int hiddenLines = region.endLine - line;

      spans.add(
        TextSpan(text: '  … END ($hiddenLines lines)', style: _foldStyle),
      );
    }

    return TextSpan(style: _baseStyle, children: spans);
  }

  Widget _buildLine(int visibleIndex) {
    final int sourceLine = _visibleLines[visibleIndex];

    final _RcFoldRegion? region = _foldRegions[sourceLine];
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
                            message: collapsed
                                ? 'Unfold section'
                                : 'Fold section',
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
        final double documentWidth = math
            .max(
              constraints.maxWidth,
              _gutterWidth + _maxLineLength * _characterWidth + 16,
            )
            .toDouble();

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
  // File loading.
  // ---------------------------------------------------------------------------

  void _loadFile() {
    _searchDebounce?.cancel();

    try {
      if (!widget.file.path.toLowerCase().endsWith('.rc')) {
        throw const FormatException('This file is not an RC resource script.');
      }

      String source = utf8.decode(widget.file.data, allowMalformed: true);

      if (source.startsWith('\uFEFF')) {
        source = source.substring(1);
      }

      final List<_RcSegment> segments = _buildSyntaxSegments(source);

      final List<int> lineStarts = [];
      final List<int> lineEnds = [];

      _buildLineIndex(source, lineStarts, lineEnds);

      final Map<int, _RcFoldRegion> foldRegions = _parseFoldRegions(
        source,
        lineStarts,
        lineEnds,
      );
      int maxLineLength = 0;

      for (int i = 0; i < lineStarts.length; i++) {
        maxLineLength = math
            .max(maxLineLength, lineEnds[i] - lineStarts[i])
            .toInt();
      }

      _searchController.clear();
      _selectedText.value = '';

      setState(() {
        _source = source;
        _lowerSource = source.toLowerCase();

        _segments = segments;
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
        _segments = [];

        _lineStarts = [0];
        _lineEnds = [0];

        _lineCount = 0;
        _maxLineLength = 0;

        _foldRegions = {};
        _collapsedLines = {};
        _visibleLines = [];
        _visibleIndexByLine = {};

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
  // Clipboard and toolbar.
  // ---------------------------------------------------------------------------

  Future<void> _copyText(String text, String message) async {
    if (text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildToolbar() {
    final bool hasMatches = _searchMatches.isNotEmpty;
    final bool hasFolds = _foldRegions.isNotEmpty;

    final bool allCollapsed =
        hasFolds && _collapsedLines.length == _foldRegions.length;

    final String matchLabel = _searchController.text.isEmpty
        ? 'Search RC'
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
                    hintText: 'Search RC...',
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
              Text(matchLabel, style: Theme.of(context).textTheme.bodySmall),
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
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'RC • $_lineCount lines • '
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
                                'Selected RC section copied.',
                              ),
                        icon: const Icon(Icons.content_copy),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Copy entire RC',
                    onPressed: _source.isEmpty
                        ? null
                        : () => _copyText(_source, 'RC file copied.'),
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
                        'Could not load RC:\n$_error',
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

class _RcSegment {
  const _RcSegment(this.start, this.end, this.style);

  final int start;
  final int end;
  final TextStyle style;
}

class _RcFoldRegion {
  const _RcFoldRegion({required this.startLine, required this.endLine});

  final int startLine;
  final int endLine;
}

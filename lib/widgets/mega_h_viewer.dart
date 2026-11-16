import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:glyphxtools/files/meg/mega_file.dart';
import 'package:material_ui/material_ui.dart';

class MegaHViewer extends StatefulWidget {
  const MegaHViewer({
    super.key,
    required this.file,
    this.backgroundColor = const Color(0xFF181818),
    this.showInfo = true,
  });

  final MegaFile file;
  final Color backgroundColor;
  final bool showInfo;

  @override
  State<MegaHViewer> createState() => _MegaHViewerState();
}

class _MegaHViewerState extends State<MegaHViewer> {
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
  static const double _gutterWidth = 60;
  static const double _characterWidth = 8.2;

  static const Color _matchColor = Color(0x665C5128);
  static const Color _activeMatchColor = Color(0xCC9A7229);

  static const TextStyle _keywordStyle = TextStyle(
    color: Color(0xFFC678DD),
  );

  static const TextStyle _typeStyle = TextStyle(
    color: Color(0xFFE5C07B),
  );

  static const TextStyle _constantStyle = TextStyle(
    color: Color(0xFF56B6C2),
  );

  static const TextStyle _stringStyle = TextStyle(
    color: Color(0xFF98C379),
  );

  static const TextStyle _numberStyle = TextStyle(
    color: Color(0xFFD19A66),
  );

  static const TextStyle _commentStyle = TextStyle(
    color: Color(0xFF5C6370),
    fontStyle: FontStyle.italic,
  );

  static const TextStyle _preprocessorStyle = TextStyle(
    color: Color(0xFFE06C75),
  );

  static const Set<String> _keywords = <String>{
    'alignas',
    'alignof',
    'and',
    'and_eq',
    'asm',
    'atomic_cancel',
    'atomic_commit',
    'atomic_noexcept',
    'auto',
    'bitand',
    'bitor',
    'break',
    'case',
    'catch',
    'class',
    'compl',
    'concept',
    'const',
    'consteval',
    'constexpr',
    'constinit',
    'const_cast',
    'continue',
    'co_await',
    'co_return',
    'co_yield',
    'decltype',
    'default',
    'delete',
    'do',
    'dynamic_cast',
    'else',
    'enum',
    'explicit',
    'export',
    'extern',
    'false',
    'final',
    'for',
    'friend',
    'goto',
    'if',
    'inline',
    'mutable',
    'namespace',
    'new',
    'noexcept',
    'not',
    'not_eq',
    'nullptr',
    'operator',
    'or',
    'or_eq',
    'override',
    'private',
    'protected',
    'public',
    'reflexpr',
    'register',
    'reinterpret_cast',
    'requires',
    'return',
    'sizeof',
    'static',
    'static_assert',
    'static_cast',
    'struct',
    'switch',
    'synchronized',
    'template',
    'this',
    'thread_local',
    'throw',
    'true',
    'try',
    'typedef',
    'typeid',
    'typename',
    'union',
    'using',
    'virtual',
    'volatile',
    'while',
    'xor',
    'xor_eq',
  };

  static const Set<String> _types = <String>{
    'bool',
    'char',
    'char8_t',
    'char16_t',
    'char32_t',
    'double',
    'float',
    'int',
    'long',
    'short',
    'signed',
    'unsigned',
    'void',
    'wchar_t',
    'size_t',
    'ptrdiff_t',
    'intptr_t',
    'uintptr_t',
    'int8_t',
    'int16_t',
    'int32_t',
    'int64_t',
    'uint8_t',
    'uint16_t',
    'uint32_t',
    'uint64_t',
  };

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

  List<_HSegment> _segments = <_HSegment>[];
  List<int> _lineStarts = <int>[0];
  List<int> _lineEnds = <int>[0];
  List<int> _visibleLines = <int>[];
  List<int> _searchMatches = <int>[];

  Map<int, _HFoldRegion> _foldRegions = <int, _HFoldRegion>{};
  Map<int, int> _visibleIndexByLine = <int, int>{};
  Set<int> _collapsedLines = <int>{};

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void didUpdateWidget(covariant MegaHViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.file, widget.file)) {
      _loadFile();
    }
  }

  // ---------------------------------------------------------------------------
  // Character helpers.
  // ---------------------------------------------------------------------------

  bool _isWhitespace(int code) {
    return code == 32 ||
        code == 9 ||
        code == 10 ||
        code == 13 ||
        code == 12;
  }

  bool _isDigit(int code) {
    return code >= 48 && code <= 57;
  }

  bool _isIdentifierStart(int code) {
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 95;
  }

  bool _isIdentifierPart(int code) {
    return _isIdentifierStart(code) || _isDigit(code);
  }

  bool _isHexDigit(int code) {
    return _isDigit(code) ||
        (code >= 65 && code <= 70) ||
        (code >= 97 && code <= 102);
  }

  // ---------------------------------------------------------------------------
  // String scanning.
  // ---------------------------------------------------------------------------

  int _rawStringPrefixLength(String source, int offset) {
    if (source.startsWith('u8R"', offset)) return 4;
    if (source.startsWith('uR"', offset)) return 3;
    if (source.startsWith('UR"', offset)) return 3;
    if (source.startsWith('LR"', offset)) return 3;
    if (source.startsWith('R"', offset)) return 2;

    return 0;
  }

  int _quotedPrefixLength(
    String source,
    int offset,
    int quoteCode,
  ) {
    if (quoteCode == 34) {
      if (source.startsWith('u8"', offset)) return 3;
      if (source.startsWith('u"', offset) ||
          source.startsWith('U"', offset) ||
          source.startsWith('L"', offset)) {
        return 2;
      }

      return 1;
    }

    if (quoteCode == 39) {
      if (source.startsWith("u'", offset) ||
          source.startsWith("U'", offset) ||
          source.startsWith("L'", offset)) {
        return 2;
      }

      return 1;
    }

    return 0;
  }

  int _scanQuotedString(
    String source,
    int quoteOffset,
  ) {
    final int quote = source.codeUnitAt(quoteOffset);
    int index = quoteOffset + 1;

    while (index < source.length) {
      final int code = source.codeUnitAt(index);

      if (code == 92) {
        index += 2;
        continue;
      }

      if (code == quote) {
        return index + 1;
      }

      index++;
    }

    return source.length;
  }

  int _scanRawString(
    String source,
    int offset,
    int prefixLength,
  ) {
    final int quoteOffset = offset + prefixLength - 1;
    final int openParen = source.indexOf('(', quoteOffset + 1);

    if (openParen == -1 || openParen - quoteOffset > 17) {
      return -1;
    }

    final String delimiter = source.substring(
      quoteOffset + 1,
      openParen,
    );

    // Raw string delimiters cannot contain whitespace, parentheses
    // or backslashes.
    for (int i = 0; i < delimiter.length; i++) {
      final int code = delimiter.codeUnitAt(i);

      if (_isWhitespace(code) ||
          code == 40 ||
          code == 41 ||
          code == 92) {
        return -1;
      }
    }

    final String closing = ')$delimiter"';

    final int closeOffset = source.indexOf(
      closing,
      openParen + 1,
    );

    if (closeOffset == -1) {
      return source.length;
    }

    return closeOffset + closing.length;
  }

  // ---------------------------------------------------------------------------
  // Preprocessor scanning.
  // ---------------------------------------------------------------------------

  bool _isPreprocessorStart(String source, int offset) {
    if (source.codeUnitAt(offset) != 35) return false;

    for (int i = offset - 1; i >= 0; i--) {
      final int code = source.codeUnitAt(i);

      if (code == 10) return true;

      if (code != 32 && code != 9 && code != 13) {
        return false;
      }
    }

    return true;
  }

  int _scanPreprocessorLine(String source, int offset) {
    int index = offset;

    while (index < source.length) {
      if (source.codeUnitAt(index) != 10) {
        index++;
        continue;
      }

      int previous = index - 1;

      if (previous >= offset &&
          source.codeUnitAt(previous) == 13) {
        previous--;
      }

      final bool continued = previous >= offset &&
          source.codeUnitAt(previous) == 92;

      index++;

      if (!continued) {
        break;
      }
    }

    return index;
  }

  // ---------------------------------------------------------------------------
  // C/C++ lexer and syntax highlighting.
  //
  // This scans the source once. It produces both syntax segments and
  // structural tokens used by the folding parser.
  // ---------------------------------------------------------------------------

  _HAnalysis _analyseSource(
    String source,
    List<int> lineStarts,
  ) {
    final List<_HSegment> segments = <_HSegment>[];
    final List<_HToken> tokens = <_HToken>[];

    void addSegment(
      int start,
      int end,
      TextStyle style,
    ) {
      if (end > start) {
        segments.add(_HSegment(start, end, style));
      }
    }

    void addToken(
      int start,
      int end, {
      bool preprocessor = false,
    }) {
      tokens.add(
        _HToken(
          start: start,
          end: end,
          text: source.substring(start, end),
          preprocessor: preprocessor,
        ),
      );
    }

    int index = 0;

    while (index < source.length) {
      final int code = source.codeUnitAt(index);

      if (_isWhitespace(code)) {
        index++;
        continue;
      }

      // Preprocessor directives, including backslash continuations.
      if (_isPreprocessorStart(source, index)) {
        final int end = _scanPreprocessorLine(source, index);

        addSegment(index, end, _preprocessorStyle);
        addToken(index, end, preprocessor: true);

        index = end;
        continue;
      }

      // Single-line comments.
      if (source.startsWith('//', index)) {
        int end = index + 2;

        while (end < source.length &&
            source.codeUnitAt(end) != 10) {
          end++;
        }

        addSegment(index, end, _commentStyle);

        index = end;
        continue;
      }

      // Multi-line comments.
      if (source.startsWith('/*', index)) {
        final int close = source.indexOf('*/', index + 2);

        final int end = close == -1
            ? source.length
            : close + 2;

        addSegment(index, end, _commentStyle);

        index = end;
        continue;
      }

      // C++ raw strings: R"...", u8R"...", LR"...", etc.
      final int rawPrefix = _rawStringPrefixLength(
        source,
        index,
      );

      if (rawPrefix > 0) {
        final int end = _scanRawString(
          source,
          index,
          rawPrefix,
        );

        if (end != -1) {
          addSegment(index, end, _stringStyle);
          addToken(index, end);

          index = end;
          continue;
        }
      }

      // Normal strings and character literals, including prefixes.
      if (code == 34 ||
          code == 39 ||
          source.startsWith('u8"', index) ||
          source.startsWith('u"', index) ||
          source.startsWith('U"', index) ||
          source.startsWith('L"', index) ||
          source.startsWith("u'", index) ||
          source.startsWith("U'", index) ||
          source.startsWith("L'", index)) {
        final int quoteCode =
            source.codeUnitAt(index + _quotedPrefixLength(
              source,
              index,
              code == 39 ? 39 : 34,
            ) - 1);

        final int prefixLength = _quotedPrefixLength(
          source,
          index,
          quoteCode,
        );

        final int quoteOffset = index + prefixLength - 1;
        final int end = _scanQuotedString(
          source,
          quoteOffset,
        );

        addSegment(index, end, _stringStyle);
        addToken(index, end);

        index = end;
        continue;
      }

      // Identifiers and C++ keywords.
      if (_isIdentifierStart(code)) {
        int end = index + 1;

        while (end < source.length &&
            _isIdentifierPart(source.codeUnitAt(end))) {
          end++;
        }

        final String token = source.substring(index, end);
        TextStyle? style;

        if (_keywords.contains(token)) {
          style = _keywordStyle;
        } else if (_types.contains(token)) {
          style = _typeStyle;
        } else if (token == token.toUpperCase() &&
            token.length > 1) {
          style = _constantStyle;
        }

        if (style != null) {
          addSegment(index, end, style);
        }

        addToken(index, end);

        index = end;
        continue;
      }

      // Numeric literals, including hexadecimal, binary, floating point
      // suffixes and digit separators.
      if (_isDigit(code) ||
          (code == 46 &&
              index + 1 < source.length &&
              _isDigit(source.codeUnitAt(index + 1)))) {
        int end = index + 1;

        while (end < source.length) {
          final int current = source.codeUnitAt(end);

          if (_isIdentifierPart(current) ||
              current == 46 ||
              current == 39) {
            end++;
            continue;
          }

          if ((current == 43 || current == 45) &&
              end > index) {
            final int previous = source.codeUnitAt(end - 1);

            if (previous == 101 ||
                previous == 69 ||
                previous == 112 ||
                previous == 80) {
              end++;
              continue;
            }
          }

          break;
        }

        addSegment(index, end, _numberStyle);
        addToken(index, end);

        index = end;
        continue;
      }

      // Keep punctuation and operators as tokens. The folding parser
      // only interprets braces, parentheses, brackets and semicolons.
      addToken(index, index + 1);
      index++;
    }

    final Map<int, _HFoldRegion> folds = _buildFoldRegions(
      tokens,
      lineStarts,
    );

    return _HAnalysis(
      segments: segments,
      folds: folds,
    );
  }

  // ---------------------------------------------------------------------------
  // Line indexing.
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

    for (int i = 0; i < ends.length; i++) {
      if (ends[i] > starts[i] &&
          source.codeUnitAt(ends[i] - 1) == 13) {
        ends[i]--;
      }
    }
  }

  int _lineForOffset(
    int offset,
    List<int> lineStarts,
  ) {
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

  // ---------------------------------------------------------------------------
  // Folding.
  //
  // Supports:
  // - class / struct / union
  // - namespace
  // - enum
  // - function bodies
  // - nested scopes and blocks
  // - initializer and lambda braces
  // - #if / #ifdef / #ifndef / #endif
  //
  // The fold arrow is placed on the first code line belonging to the
  // block declaration, not necessarily on the line containing '{'.
  // ---------------------------------------------------------------------------

  Map<int, _HFoldRegion> _buildFoldRegions(
    List<_HToken> tokens,
    List<int> lineStarts,
  ) {
    final Map<int, _HFoldRegion> regions =
        <int, _HFoldRegion>{};

    final List<_HOpenBlock> braceStack = <_HOpenBlock>[];
    final List<int> preprocessorStack = <int>[];

    int? statementStartOffset;
    int parenthesisDepth = 0;
    int bracketDepth = 0;

    void addRegion(int startLine, int endLine) {
      if (endLine <= startLine) return;

      final _HFoldRegion? previous = regions[startLine];

      // When multiple blocks start on the same line, use the outermost
      // region so one fold action hides the complete line's block.
      if (previous == null || endLine > previous.endLine) {
        regions[startLine] = _HFoldRegion(
          startLine: startLine,
          endLine: endLine,
        );
      }
    }

    final RegExp preprocessorPattern = RegExp(
      r'^\s*#\s*(if|ifdef|ifndef|endif)\b',
      caseSensitive: false,
    );

    for (final _HToken token in tokens) {
      if (token.preprocessor) {
        final Match? directive = preprocessorPattern.firstMatch(
          token.text,
        );

        if (directive == null) continue;

        final String name = directive.group(1)!.toLowerCase();
        final int line = _lineForOffset(
          token.start,
          lineStarts,
        );

        if (name == 'if' ||
            name == 'ifdef' ||
            name == 'ifndef') {
          preprocessorStack.add(line);
        } else if (name == 'endif' &&
            preprocessorStack.isNotEmpty) {
          final int startLine = preprocessorStack.removeLast();
          addRegion(startLine, line);
        }

        continue;
      }

      final String text = token.text;

      if (text == '{') {
        final int declarationOffset =
            statementStartOffset ?? token.start;

        final int declarationLine = _lineForOffset(
          declarationOffset,
          lineStarts,
        );

        braceStack.add(
          _HOpenBlock(
            line: declarationLine,
          ),
        );

        statementStartOffset = null;
        continue;
      }

      if (text == '}') {
        if (braceStack.isNotEmpty) {
          final _HOpenBlock opening = braceStack.removeLast();

          final int closingLine = _lineForOffset(
            token.start,
            lineStarts,
          );

          addRegion(opening.line, closingLine);
        }

        statementStartOffset = null;
        continue;
      }

      if (text == ';' &&
          parenthesisDepth == 0 &&
          bracketDepth == 0) {
        statementStartOffset = null;
        continue;
      }

      if (statementStartOffset == null) {
        statementStartOffset = token.start;
      }

      if (text == '(') {
        parenthesisDepth++;
      } else if (text == ')' && parenthesisDepth > 0) {
        parenthesisDepth--;
      } else if (text == '[') {
        bracketDepth++;
      } else if (text == ']' && bracketDepth > 0) {
        bracketDepth--;
      }
    }

    return regions;
  }

  void _rebuildVisibleLines() {
    final List<int> lines = <int>[];
    final Map<int, int> indexByLine = <int, int>{};

    int line = 0;

    while (line < _lineStarts.length) {
      indexByLine[line] = lines.length;
      lines.add(line);

      final _HFoldRegion? region = _foldRegions[line];

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

    final List<int> collapsed =
        _collapsedLines.toList(growable: false);

    for (final int startLine in collapsed) {
      final _HFoldRegion? region = _foldRegions[startLine];

      if (region != null &&
          line > startLine &&
          line <= region.endLine) {
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

    _searchDebounce = Timer(
      const Duration(milliseconds: 200),
      () {
        if (mounted) {
          _performSearch(query);
        }
      },
    );
  }

  void _performSearch(String query) {
    final String needle = query.toLowerCase();
    final List<int> matches = <int>[];

    if (needle.isNotEmpty) {
      int offset = 0;

      while (offset <= _lowerSource.length - needle.length) {
        final int index = _lowerSource.indexOf(
          needle,
          offset,
        );

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
      changed = _expandCollapsedForLine(
        _lineForOffset(
          matches.first,
          _lineStarts,
        ),
      );
    }

    if (changed) {
      _rebuildVisibleLines();
    }

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
          (_currentMatchIndex + direction) %
              _searchMatches.length;

      if (_currentMatchIndex < 0) {
        _currentMatchIndex += _searchMatches.length;
      }

      final int line = _lineForOffset(
        _searchMatches[_currentMatchIndex],
        _lineStarts,
      );

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
    if (_currentMatchIndex < 0 ||
        _searchMatches.isEmpty) {
      return;
    }

    final int sourceLine = _lineForOffset(
      _searchMatches[_currentMatchIndex],
      _lineStarts,
    );

    final int? visibleIndex =
        _visibleIndexByLine[sourceLine];

    if (visibleIndex == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalController.hasClients) {
        return;
      }

      final ScrollPosition position =
          _verticalController.position;

      final double target = (
        visibleIndex * _lineHeight -
        position.viewportDimension * 0.35
      ).clamp(
        0.0,
        position.maxScrollExtent,
      ).toDouble();

      _verticalController.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Efficient syntax rendering.
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

    final List<InlineSpan> spans = <InlineSpan>[];

    int position = start;
    int segmentIndex = _firstSegmentEndingAfter(start);
    int matchIndex = _firstMatchEndingAfter(start);

    while (position < end) {
      while (segmentIndex < _segments.length &&
          _segments[segmentIndex].end <= position) {
        segmentIndex++;
      }

      final _HSegment? segment =
          segmentIndex < _segments.length
              ? _segments[segmentIndex]
              : null;

      TextStyle syntaxStyle = _baseStyle;
      int segmentEnd = end;

      if (segment != null) {
        if (segment.start > position) {
          segmentEnd = math.min(
            end,
            segment.start,
          ).toInt();
        } else {
          syntaxStyle = segment.style;
          segmentEnd = math.min(
            end,
            segment.end,
          ).toInt();
        }
      }

      if (segmentEnd <= position) break;

      while (position < segmentEnd) {
        while (matchIndex < _searchMatches.length &&
            _searchMatches[matchIndex] + _searchLength <=
                position) {
          matchIndex++;
        }

        int pieceEnd = segmentEnd;
        TextStyle pieceStyle = syntaxStyle;

        if (matchIndex < _searchMatches.length &&
            _searchMatches[matchIndex] <= position &&
            _searchMatches[matchIndex] + _searchLength >
                position) {
          pieceEnd = math.min(
            segmentEnd,
            _searchMatches[matchIndex] + _searchLength,
          ).toInt();

          pieceStyle = syntaxStyle.copyWith(
            backgroundColor:
                matchIndex == _currentMatchIndex
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

    final _HFoldRegion? region = _foldRegions[line];

    if (region != null && _collapsedLines.contains(line)) {
      final int hiddenLines = region.endLine - line;

      spans.add(
        TextSpan(
          text: '  … } ($hiddenLines lines)',
          style: _foldStyle,
        ),
      );
    }

    return TextSpan(
      style: _baseStyle,
      children: spans,
    );
  }

  Widget _buildLine(int visibleIndex) {
    final int sourceLine = _visibleLines[visibleIndex];

    final _HFoldRegion? region = _foldRegions[sourceLine];
    final bool collapsed =
        _collapsedLines.contains(sourceLine);

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
        final double documentWidth = math.max(
          constraints.maxWidth,
          _gutterWidth +
              _maxLineLength * _characterWidth +
              16,
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
                    final String selected =
                        content?.plainText ?? '';

                    if (_selectedText.value != selected) {
                      _selectedText.value = selected;
                    }
                  },
                  child: ListView.builder(
                    controller: _verticalController,
                    itemCount: _visibleLines.length,
                    itemExtent: _lineHeight,
                    itemBuilder: (context, index) =>
                        _buildLine(index),
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
      final String lowerPath =
          widget.file.path.toLowerCase();

      const Set<String> supportedExtensions = <String>{
        '.h',
        '.hh',
        '.hpp',
        '.hxx',
        '.h++',
      };

      final bool supported = supportedExtensions.any(
        (String extension) => lowerPath.endsWith(extension),
      );

      if (!supported) {
        throw const FormatException(
          'This file is not a supported C/C++ header.',
        );
      }

      String source = utf8.decode(
        widget.file.data,
        allowMalformed: true,
      );

      if (source.startsWith('\uFEFF')) {
        source = source.substring(1);
      }

      final List<int> lineStarts = <int>[];
      final List<int> lineEnds = <int>[];

      _buildLineIndex(
        source,
        lineStarts,
        lineEnds,
      );

      final _HAnalysis analysis = _analyseSource(
        source,
        lineStarts,
      );

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

        _segments = analysis.segments;
        _lineStarts = lineStarts;
        _lineEnds = lineEnds;

        _lineCount = lineStarts.length;
        _maxLineLength = maxLineLength;

        _foldRegions = analysis.folds;
        _collapsedLines.clear();

        _searchMatches = <int>[];
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
        _segments = <_HSegment>[];

        _lineStarts = <int>[0];
        _lineEnds = <int>[0];

        _lineCount = 0;
        _maxLineLength = 0;

        _foldRegions = <int, _HFoldRegion>{};
        _collapsedLines = <int>{};
        _visibleLines = <int>[];
        _visibleIndexByLine = <int, int>{};

        _searchMatches = <int>[];
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

  Future<void> _copyText(
    String text,
    String message,
  ) async {
    if (text.isEmpty) return;

    await Clipboard.setData(
      ClipboardData(text: text),
    );

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

    final bool allCollapsed = hasFolds &&
        _collapsedLines.length == _foldRegions.length;

    final String matchLabel =
        _searchController.text.isEmpty
            ? 'Search C++'
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
                    hintText: 'Search header...',
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
                onPressed: hasMatches
                    ? () => _navigateMatch(-1)
                    : null,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: 'Next match',
                onPressed: hasMatches
                    ? () => _navigateMatch(1)
                    : null,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: !hasFolds || allCollapsed
                    ? null
                    : _foldAll,
                icon: const Icon(Icons.unfold_less),
                label: const Text('Fold All'),
              ),
              TextButton.icon(
                onPressed: _collapsedLines.isEmpty
                    ? null
                    : _unfoldAll,
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
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium,
                        ),
                        Text(
                          'C/C++ Header • $_lineCount lines • '
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
                                  'Selected code copied.',
                                ),
                        icon: const Icon(Icons.content_copy),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Copy entire header',
                    onPressed: _source.isEmpty
                        ? null
                        : () => _copyText(
                              _source,
                              'Header file copied.',
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
                        'Could not load header:\n$_error',
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

class _HSegment {
  const _HSegment(
    this.start,
    this.end,
    this.style,
  );

  final int start;
  final int end;
  final TextStyle style;
}

class _HToken {
  const _HToken({
    required this.start,
    required this.end,
    required this.text,
    this.preprocessor = false,
  });

  final int start;
  final int end;
  final String text;
  final bool preprocessor;
}

class _HOpenBlock {
  const _HOpenBlock({
    required this.line,
  });

  final int line;
}

class _HFoldRegion {
  const _HFoldRegion({
    required this.startLine,
    required this.endLine,
  });

  final int startLine;
  final int endLine;
}

class _HAnalysis {
  const _HAnalysis({
    required this.segments,
    required this.folds,
  });

  final List<_HSegment> segments;
  final Map<int, _HFoldRegion> folds;
}
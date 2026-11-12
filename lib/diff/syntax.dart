import 'dart:typed_data';

/// Minimal, allocation-light tokenizers. Not a full grammar: the goal is
/// readable diffs at zero perceptible cost, computed once in the parse isolate.
enum SyntaxLanguage { js, css }

abstract final class TokenKind {
  static const keyword = 1;
  static const string = 2;
  static const comment = 3;
  static const number = 4;
  static const function = 5;
  static const type = 6;
  static const property = 7;
  static const punctuation = 8;
}

SyntaxLanguage? languageForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  switch (path.substring(dot + 1).toLowerCase()) {
    case 'js' || 'jsx' || 'mjs' || 'cjs' || 'ts' || 'tsx' || 'mts' || 'cts':
      return SyntaxLanguage.js;
    case 'css' || 'scss' || 'less':
      return SyntaxLanguage.css;
  }
  return null;
}

class TokenizeResult {
  const TokenizeResult(this.spans, this.state);
  final Int32List? spans;

  /// 0 = normal, 1 = inside block comment, 2 = inside template literal.
  final int state;
}

const _jsKeywords = {
  'abstract',
  'any',
  'as',
  'async',
  'await',
  'boolean',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'constructor',
  'continue',
  'debugger',
  'declare',
  'default',
  'delete',
  'do',
  'else',
  'enum',
  'export',
  'extends',
  'false',
  'finally',
  'for',
  'from',
  'function',
  'get',
  'if',
  'implements',
  'import',
  'in',
  'infer',
  'instanceof',
  'interface',
  'is',
  'keyof',
  'let',
  'module',
  'namespace',
  'never',
  'new',
  'null',
  'number',
  'object',
  'of',
  'override',
  'private',
  'protected',
  'public',
  'readonly',
  'return',
  'satisfies',
  'set',
  'static',
  'string',
  'super',
  'switch',
  'symbol',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'typeof',
  'undefined',
  'unique',
  'unknown',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

TokenizeResult tokenizeLine(String s, SyntaxLanguage lang, int state) =>
    lang == SyntaxLanguage.js ? _tokenizeJs(s, state) : _tokenizeCss(s, state);

bool _isIdentStart(int c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127;
bool _isIdent(int c) => _isIdentStart(c) || (c >= 48 && c <= 57);
bool _isDigit(int c) => c >= 48 && c <= 57;

TokenizeResult _tokenizeJs(String s, int state) {
  final out = <int>[];
  final n = s.length;
  var i = 0;

  void emit(int a, int b, int k) {
    if (b > a) {
      out
        ..add(a)
        ..add(b)
        ..add(k);
    }
  }

  if (state == 1) {
    final end = s.indexOf('*/');
    if (end < 0) {
      emit(0, n, TokenKind.comment);
      return TokenizeResult(_pack(out), 1);
    }
    emit(0, end + 2, TokenKind.comment);
    i = end + 2;
    state = 0;
  } else if (state == 2) {
    final (end, closed) = _scan(s, 0, 96);
    emit(0, end, TokenKind.string);
    if (!closed) return TokenizeResult(_pack(out), 2);
    i = end;
    state = 0;
  }

  while (i < n) {
    final c = s.codeUnitAt(i);
    if (c == 47 && i + 1 < n) {
      final d = s.codeUnitAt(i + 1);
      if (d == 47) {
        emit(i, n, TokenKind.comment);
        break;
      }
      if (d == 42) {
        final end = s.indexOf('*/', i + 2);
        if (end < 0) {
          emit(i, n, TokenKind.comment);
          return TokenizeResult(_pack(out), 1);
        }
        emit(i, end + 2, TokenKind.comment);
        i = end + 2;
        continue;
      }
    }
    if (c == 34 || c == 39) {
      final end = _scan(s, i + 1, c).$1;
      emit(i, end, TokenKind.string);
      i = end;
      continue;
    }
    if (c == 96) {
      final (end, closed) = _scan(s, i + 1, 96);
      emit(i, end, TokenKind.string);
      if (!closed) return TokenizeResult(_pack(out), 2);
      i = end;
      continue;
    }
    if (_isDigit(c) || (c == 46 && i + 1 < n && _isDigit(s.codeUnitAt(i + 1)))) {
      if (i > 0 && _isIdent(s.codeUnitAt(i - 1))) {
        i++;
        continue;
      }
      var j = i + 1;
      while (j < n && (_isIdent(s.codeUnitAt(j)) || s.codeUnitAt(j) == 46)) {
        j++;
      }
      emit(i, j, TokenKind.number);
      i = j;
      continue;
    }
    if (_isIdentStart(c)) {
      var j = i + 1;
      while (j < n && _isIdent(s.codeUnitAt(j))) {
        j++;
      }
      final word = s.substring(i, j);
      final prevDot = i > 0 && s.codeUnitAt(i - 1) == 46;
      if (!prevDot && _jsKeywords.contains(word)) {
        emit(i, j, TokenKind.keyword);
      } else {
        var k = j;
        while (k < n && s.codeUnitAt(k) == 32) {
          k++;
        }
        if (k < n && (s.codeUnitAt(k) == 40 || (s.codeUnitAt(k) == 60 && c >= 97))) {
          emit(i, j, TokenKind.function);
        } else if (c >= 65 && c <= 90) {
          emit(i, j, TokenKind.type);
        }
      }
      i = j;
      continue;
    }
    i++;
  }
  return TokenizeResult(_pack(out), 0);
}

TokenizeResult _tokenizeCss(String s, int state) {
  final out = <int>[];
  final n = s.length;
  var i = 0;

  void emit(int a, int b, int k) {
    if (b > a) {
      out
        ..add(a)
        ..add(b)
        ..add(k);
    }
  }

  if (state == 1) {
    final end = s.indexOf('*/');
    if (end < 0) {
      emit(0, n, TokenKind.comment);
      return TokenizeResult(_pack(out), 1);
    }
    emit(0, end + 2, TokenKind.comment);
    i = end + 2;
  }
  final hasBrace = s.contains('{');

  while (i < n) {
    final c = s.codeUnitAt(i);
    if (c == 47 && i + 1 < n && s.codeUnitAt(i + 1) == 42) {
      final end = s.indexOf('*/', i + 2);
      if (end < 0) {
        emit(i, n, TokenKind.comment);
        return TokenizeResult(_pack(out), 1);
      }
      emit(i, end + 2, TokenKind.comment);
      i = end + 2;
      continue;
    }
    if (c == 47 && i + 1 < n && s.codeUnitAt(i + 1) == 47) {
      emit(i, n, TokenKind.comment); // scss / less line comments
      break;
    }
    if (c == 34 || c == 39) {
      final end = _scan(s, i + 1, c).$1;
      emit(i, end, TokenKind.string);
      i = end;
      continue;
    }
    if (c == 64 || c == 33) {
      // @media, !important
      var j = i + 1;
      while (j < n && (_isIdent(s.codeUnitAt(j)) || s.codeUnitAt(j) == 45)) {
        j++;
      }
      emit(i, j, TokenKind.keyword);
      i = j;
      continue;
    }
    if (c == 35 && !hasBrace) {
      var j = i + 1;
      while (j < n && _isIdent(s.codeUnitAt(j))) {
        j++;
      }
      emit(i, j, TokenKind.number); // hex color
      i = j;
      continue;
    }
    if (_isDigit(c) || (c == 46 && i + 1 < n && _isDigit(s.codeUnitAt(i + 1)))) {
      if (i > 0 && (_isIdent(s.codeUnitAt(i - 1)) || s.codeUnitAt(i - 1) == 45)) {
        i++;
        continue;
      }
      var j = i + 1;
      while (j < n && (_isIdent(s.codeUnitAt(j)) || s.codeUnitAt(j) == 46 || s.codeUnitAt(j) == 37)) {
        j++;
      }
      emit(i, j, TokenKind.number);
      i = j;
      continue;
    }
    if (_isIdentStart(c) || c == 45) {
      var j = i + 1;
      while (j < n && (_isIdent(s.codeUnitAt(j)) || s.codeUnitAt(j) == 45)) {
        j++;
      }
      var k = j;
      while (k < n && s.codeUnitAt(k) == 32) {
        k++;
      }
      if (k < n && s.codeUnitAt(k) == 40) {
        emit(i, j, TokenKind.function);
      } else if (!hasBrace && k < n && s.codeUnitAt(k) == 58 && (k + 1 >= n || s.codeUnitAt(k + 1) != 58)) {
        emit(i, j, TokenKind.property);
      }
      i = j;
      continue;
    }
    i++;
  }
  return TokenizeResult(_pack(out), 0);
}

/// Returns the index just past the closing [quote] and whether it was found.
(int, bool) _scan(String s, int from, int quote) {
  var j = from;
  final n = s.length;
  while (j < n) {
    final ch = s.codeUnitAt(j);
    if (ch == 92) {
      j += 2;
      continue;
    }
    j++;
    if (ch == quote) return (j, true);
  }
  return (n, false);
}

Int32List? _pack(List<int> v) => v.isEmpty ? null : Int32List.fromList(v);

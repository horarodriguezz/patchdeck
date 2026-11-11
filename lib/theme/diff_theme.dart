import 'package:flutter/material.dart';

/// Colors used by the diff renderer, exposed as a [ThemeExtension].
@immutable
class DiffTheme extends ThemeExtension<DiffTheme> {
  const DiffTheme({
    required this.codeBg,
    required this.codeFg,
    required this.lineNoFg,
    required this.addBg,
    required this.addGutterBg,
    required this.delBg,
    required this.delGutterBg,
    required this.hunkBg,
    required this.hunkFg,
    required this.emptyBg,
    required this.selectedBg,
    required this.selectedGutterBg,
    required this.fileHeaderBg,
    required this.border,
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.function,
    required this.typeName,
    required this.property,
  });

  final Color codeBg, codeFg, lineNoFg;
  final Color addBg, addGutterBg, delBg, delGutterBg;
  final Color hunkBg, hunkFg, emptyBg;
  final Color selectedBg, selectedGutterBg;
  final Color fileHeaderBg, border;
  final Color keyword, string, comment, number, function, typeName, property;

  /// Indexed by `TokenKind` (see diff/syntax.dart).
  List<Color?> get tokenColors => [null, keyword, string, comment, number, function, typeName, property, null];

  @override
  DiffTheme copyWith() => this;

  @override
  DiffTheme lerp(DiffTheme? other, double t) => t < 0.5 || other == null ? this : other;
}

extension DiffThemeX on BuildContext {
  DiffTheme get diffTheme => Theme.of(this).extension<DiffTheme>()!;
}

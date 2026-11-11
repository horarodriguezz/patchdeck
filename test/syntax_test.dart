import 'package:flutter_test/flutter_test.dart';
import 'package:patchdeck/diff/syntax.dart';

List<(String, int)> tokens(String s, SyntaxLanguage l, [int state = 0]) {
  final r = tokenizeLine(s, l, state);
  final sp = r.spans;
  if (sp == null) return [];
  return [for (var i = 0; i < sp.length; i += 3) (s.substring(sp[i], sp[i + 1]), sp[i + 2])];
}

void main() {
  test('language detection', () {
    expect(languageForPath('a/b.tsx'), SyntaxLanguage.js);
    expect(languageForPath('x.MJS'), SyntaxLanguage.js);
    expect(languageForPath('s.scss'), SyntaxLanguage.css);
    expect(languageForPath('README.md'), isNull);
  });

  test('js tokens', () {
    final t = tokens('export const x: Foo = bar(1, "s"); // c', SyntaxLanguage.js);
    expect(t, contains(('export', TokenKind.keyword)));
    expect(t, contains(('Foo', TokenKind.type)));
    expect(t, contains(('bar', TokenKind.function)));
    expect(t, contains(('1', TokenKind.number)));
    expect(t, contains(('"s"', TokenKind.string)));
    expect(t.last, ('// c', TokenKind.comment));
  });

  test('block comment and template literal carry state', () {
    expect(tokenizeLine('a /* open', SyntaxLanguage.js, 0).state, 1);
    expect(tokenizeLine('still */ b', SyntaxLanguage.js, 1).state, 0);
    expect(tokenizeLine('x = `multi', SyntaxLanguage.js, 0).state, 2);
    expect(tokenizeLine('line`;', SyntaxLanguage.js, 2).state, 0);
    expect(tokenizeLine('y = `one`;', SyntaxLanguage.js, 0).state, 0);
  });

  test('css tokens', () {
    final t = tokens('  color: #fff !important; margin: 4px;', SyntaxLanguage.css);
    expect(t, contains(('color', TokenKind.property)));
    expect(t, contains(('#fff', TokenKind.number)));
    expect(t, contains(('!important', TokenKind.keyword)));
    expect(t, contains(('4px', TokenKind.number)));
  });
}

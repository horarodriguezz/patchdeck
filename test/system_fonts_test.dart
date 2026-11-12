import 'package:flutter_test/flutter_test.dart';
import 'package:patchdeck/services/system_fonts.dart';

void main() {
  test('parses desktop font specs', () {
    expect(parseFontSpec("'Cantarell 11'"), 'Cantarell');
    expect(parseFontSpec("'Ubuntu Mono 13'"), 'Ubuntu Mono');
    expect(parseFontSpec("'Adwaita Sans 10.5'"), 'Adwaita Sans');
    expect(parseFontSpec("''"), isNull);
  });
}

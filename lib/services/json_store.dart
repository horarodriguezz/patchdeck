import 'dart:convert';
import 'dart:io';

/// Atomic JSON persistence: write to a temp file, then rename over the
/// target, so a crash never leaves a truncated document behind.
abstract final class JsonStore {
  static const _encoder = JsonEncoder.withIndent('  ');

  static Future<Object?> read(File file) async {
    try {
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } on FormatException {
      // Keep the broken file around for manual recovery.
      await file.rename('${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      return null;
    }
  }

  static Future<void> write(File file, Object json, {bool pretty = true}) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(pretty ? _encoder.convert(json) : jsonEncode(json), flush: true);
    await tmp.rename(file.path);
  }
}

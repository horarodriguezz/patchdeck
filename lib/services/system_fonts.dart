import 'dart:io';

/// The desktop's configured UI and monospace font families.
///
/// Flutter on Linux resolves family names through fontconfig, so passing the
/// names the desktop uses makes the app match the rest of the system.
class SystemFonts {
  const SystemFonts({this.ui, this.mono, this.source = 'predeterminada'});

  final String? ui;
  final String? mono;

  /// Where the values came from (shown in Settings).
  final String source;

  static SystemFonts current = const SystemFonts();

  /// Order: KDE (`kdeglobals`) on Plasma, GNOME-family `gsettings`, then
  /// fontconfig aliases (`fc-match sans-serif` / `monospace`). Never throws,
  /// and every external call is time-boxed so startup can't hang.
  static Future<SystemFonts> detect() async {
    try {
      final desktop = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase();
      String? ui, mono;
      var source = '';

      if (desktop.contains('kde')) {
        final kde = await _fromKdeGlobals();
        ui = kde.$1;
        mono = kde.$2;
        if (ui != null) source = 'KDE';
      }
      if (ui == null || mono == null) {
        final g = await Future.wait([
          _gsettings('font-name'),
          _gsettings('monospace-font-name'),
        ]);
        if (ui == null && g[0] != null) {
          ui = g[0];
          source = source.isEmpty ? 'GNOME' : source;
        }
        mono ??= g[1];
      }
      if (ui == null || mono == null) {
        final fc = await Future.wait([_fcMatch('sans-serif'), _fcMatch('monospace')]);
        if (ui == null && fc[0] != null) {
          ui = fc[0];
          source = source.isEmpty ? 'fontconfig' : source;
        }
        mono ??= fc[1];
      }
      return SystemFonts(ui: ui, mono: mono, source: source.isEmpty ? 'predeterminada' : source);
    } catch (_) {
      return const SystemFonts();
    }
  }

  static Future<String?> _run(String exe, List<String> args) async {
    try {
      final r = await Process.run(exe, args).timeout(const Duration(milliseconds: 800));
      if (r.exitCode != 0) return null;
      final out = (r.stdout as String).trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _gsettings(String key) async {
    final v = await _run('gsettings', ['get', 'org.gnome.desktop.interface', key]);
    return v == null ? null : parseFontSpec(v);
  }

  static Future<String?> _fcMatch(String alias) => _run('fc-match', ['-f', '%{family[0]}', alias]);

  static Future<(String?, String?)> _fromKdeGlobals() async {
    final home = Platform.environment['HOME'];
    final cfg = Platform.environment['XDG_CONFIG_HOME'] ?? (home == null ? null : '$home/.config');
    if (cfg == null) return (null, null);
    final f = File('$cfg/kdeglobals');
    if (!await f.exists()) return (null, null);
    String? ui, mono;
    for (final line in await f.readAsLines()) {
      if (line.startsWith('font=')) ui = line.substring(5).split(',').first.trim();
      if (line.startsWith('fixed=')) mono = line.substring(6).split(',').first.trim();
    }
    return (ui == '' ? null : ui, mono == '' ? null : mono);
  }
}

/// `'Cantarell 11'` → `Cantarell`, `'Ubuntu Mono 13'` → `Ubuntu Mono`.
String? parseFontSpec(String raw) {
  var s = raw.trim();
  if (s.length >= 2 && (s.startsWith("'") || s.startsWith('"'))) s = s.substring(1, s.length - 1);
  s = s.replaceFirst(RegExp(r'\s+\d+(\.\d+)?$'), '').trim();
  return s.isEmpty ? null : s;
}

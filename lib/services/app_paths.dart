import 'dart:io';

/// Where settings and reviews live.
///
/// Linux (XDG Base Directory):
/// * Settings (small, hand-editable): `$XDG_CONFIG_HOME/patchdeck/settings.json`
/// * Reviews (data, can be big):     `$XDG_DATA_HOME/patchdeck/reviews/<id>.json`
///
/// Windows: both under `%APPDATA%\Patchdeck\`.
class AppPaths {
  AppPaths({required this.configDir, required this.dataDir});

  static const appDirName = 'patchdeck';

  final Directory configDir;
  final Directory dataDir;

  factory AppPaths.fromEnvironment() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      // %APPDATA%\Patchdeck\settings.json and %APPDATA%\Patchdeck\reviews\
      final appData = env['APPDATA'] ?? '${env['USERPROFILE'] ?? Directory.current.path}\\AppData\\Roaming';
      final dir = Directory('$appData\\Patchdeck');
      return AppPaths(configDir: dir, dataDir: dir);
    }
    final home = env['HOME'] ?? Directory.current.path;
    String xdg(String key, String fallback) {
      final v = env[key];
      return (v != null && v.isNotEmpty) ? v : '$home/$fallback';
    }

    return AppPaths(
      configDir: Directory('${xdg('XDG_CONFIG_HOME', '.config')}/$appDirName'),
      dataDir: Directory('${xdg('XDG_DATA_HOME', '.local/share')}/$appDirName'),
    );
  }

  File get settingsFile => File('${configDir.path}/settings.json');
  Directory get reviewsDir => Directory('${dataDir.path}/reviews');
  File get reviewsIndex => File('${dataDir.path}/reviews/index.json');
  File reviewFile(String id) => File('${reviewsDir.path}/$id.json');
}

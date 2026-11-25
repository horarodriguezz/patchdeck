import 'dart:async';

import '../models/app_settings.dart';
import 'app_paths.dart';
import 'dir_watcher.dart';
import 'json_store.dart';

class SettingsRepository {
  SettingsRepository(this.paths);
  final AppPaths paths;

  FileStamp? _known;
  bool _knownSet = false;
  DirWatcher? _watcher;
  final StreamController<AppSettings> _changes = StreamController.broadcast();

  /// settings.json rewritten by another process (only emitted after [watch]).
  Stream<AppSettings> get changes => _changes.stream;

  Future<AppSettings> load() async {
    final stamp = await JsonStore.stamp(paths.settingsFile);
    final json = await JsonStore.read(paths.settingsFile);
    _remember(stamp);
    if (json is Map<String, dynamic>) return AppSettings.fromJson(json);
    return AppSettings.defaults();
  }

  Future<void> save(AppSettings s) async {
    await JsonStore.write(paths.settingsFile, s.toJson());
    _remember(await JsonStore.stamp(paths.settingsFile));
  }

  void _remember(FileStamp? s) {
    _known = s;
    _knownSet = true;
  }

  /// Whether settings.json changed since we last read or wrote it.
  Future<bool> changedOnDisk() async => !_knownSet || await JsonStore.stamp(paths.settingsFile) != _known;

  Future<void> watch() async {
    if (_watcher != null) return;
    final w = _watcher = DirWatcher(paths.configDir, accept: (name) => name == 'settings.json');
    w.changes.listen((_) => _onFileChanged());
    await w.start();
  }

  Future<void> _onFileChanged() async {
    final stamp = await JsonStore.stamp(paths.settingsFile);
    if (stamp == null || (_knownSet && stamp == _known)) return;
    final s = await load();
    if (!_changes.isClosed) _changes.add(s);
  }

  Future<void> dispose() async {
    await _watcher?.dispose();
    _watcher = null;
    await _changes.close();
  }
}

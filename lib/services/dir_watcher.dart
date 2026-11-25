import 'dart:async';
import 'dart:io';

/// Watches a directory and reports, debounced, the paths of files whose name
/// passes [accept] that were created, modified, moved into place or deleted.
///
/// Atomic writes (temp file + rename) show up as a move whose destination is
/// the real file, so both the event path and the move destination are checked.
class DirWatcher {
  DirWatcher(this.dir, {required this.accept, this.debounce = const Duration(milliseconds: 150)});

  final Directory dir;
  final bool Function(String name) accept;
  final Duration debounce;

  final StreamController<String> _changes = StreamController.broadcast();
  final Map<String, Timer> _timers = {};
  StreamSubscription<FileSystemEvent>? _sub;

  Stream<String> get changes => _changes.stream;

  static String baseName(String path) => path.split(RegExp(r'[\\/]')).last;

  /// Starts watching; returns false when the platform can't watch [dir].
  Future<bool> start() async {
    if (_sub != null) return true;
    try {
      await dir.create(recursive: true);
      _sub = dir.watch().listen(_onEvent, onError: (Object _) {});
      return true;
    } on FileSystemException {
      return false;
    }
  }

  void _onEvent(FileSystemEvent e) {
    _touch(e.path);
    if (e is FileSystemMoveEvent && e.destination != null) _touch(e.destination!);
  }

  void _touch(String path) {
    if (!accept(baseName(path))) return;
    _timers[path]?.cancel();
    _timers[path] = Timer(debounce, () {
      _timers.remove(path);
      if (!_changes.isClosed) _changes.add(path);
    });
  }

  Future<void> dispose() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    await _sub?.cancel();
    _sub = null;
    await _changes.close();
  }
}

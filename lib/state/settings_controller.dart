import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/ids.dart';
import '../models/label.dart';
import '../services/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repo, this._settings);

  final SettingsRepository _repo;
  AppSettings _settings;
  Timer? _saveTimer;

  AppSettings get settings => _settings;
  List<ReviewLabel> get labels => _settings.labels;

  ReviewLabel? labelById(String id) {
    for (final l in _settings.labels) {
      if (l.id == id) return l;
    }
    return null;
  }

  void update(AppSettings s) {
    _settings = s;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () => _repo.save(_settings));
  }

  void setTheme(String id) => update(_settings.copyWith(themeId: id));
  void setFontSize(double v) => update(_settings.copyWith(codeFontSize: v));
  void setDiffMode(DiffMode m) => update(_settings.copyWith(diffMode: m));
  void setSyntaxHighlight(bool v) => update(_settings.copyWith(syntaxHighlight: v));
  void setCodeFont(String family) => update(_settings.copyWith(codeFontFamily: family.trim()));
  void setCopyTemplate(String template) => update(_settings.copyWith(copyTemplate: template));

  void upsertLabel({String? id, required String title, required String description, required int color}) {
    final labels = List.of(_settings.labels);
    final i = id == null ? -1 : labels.indexWhere((l) => l.id == id);
    if (i >= 0) {
      labels[i] = labels[i].copyWith(title: title, description: description, color: color);
    } else {
      labels.add(ReviewLabel(id: newId(), title: title, description: description, color: color));
    }
    update(_settings.copyWith(labels: labels));
  }

  void deleteLabel(String id) => update(
    _settings.copyWith(
      labels: [
        for (final l in _settings.labels)
          if (l.id != id) l,
      ],
    ),
  );

  void reorderLabel(int oldIndex, int newIndex) {
    final labels = List.of(_settings.labels);
    if (newIndex > oldIndex) newIndex--;
    labels.insert(newIndex, labels.removeAt(oldIndex));
    update(_settings.copyWith(labels: labels));
  }

  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _repo.save(_settings);
    }
  }
}

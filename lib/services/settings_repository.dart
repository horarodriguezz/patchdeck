import '../models/app_settings.dart';
import 'app_paths.dart';
import 'json_store.dart';

class SettingsRepository {
  SettingsRepository(this.paths);
  final AppPaths paths;

  Future<AppSettings> load() async {
    final json = await JsonStore.read(paths.settingsFile);
    if (json is Map<String, dynamic>) return AppSettings.fromJson(json);
    return AppSettings.defaults();
  }

  Future<void> save(AppSettings s) => JsonStore.write(paths.settingsFile, s.toJson());
}

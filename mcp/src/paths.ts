import os from 'node:os';
import path from 'node:path';

/**
 * Where Patchdeck keeps its data — mirrors `lib/services/app_paths.dart`.
 *
 * Linux (XDG): `$XDG_CONFIG_HOME/patchdeck/settings.json` and
 * `$XDG_DATA_HOME/patchdeck/reviews/<id>.json`. Windows: `%APPDATA%\Patchdeck\`.
 *
 * `PATCHDECK_CONFIG_DIR` / `PATCHDECK_DATA_DIR` override both (useful for tests
 * or a portable install).
 */
export interface Paths {
  configDir: string;
  dataDir: string;
  settingsFile: string;
  reviewsDir: string;
  reviewsIndex: string;
  reviewFile(id: string): string;
}

export function makePaths(configDir: string, dataDir: string): Paths {
  const reviewsDir = path.join(dataDir, 'reviews');
  return {
    configDir,
    dataDir,
    settingsFile: path.join(configDir, 'settings.json'),
    reviewsDir,
    reviewsIndex: path.join(reviewsDir, 'index.json'),
    reviewFile: (id) => path.join(reviewsDir, `${id}.json`),
  };
}

export function pathsFromEnv(env: NodeJS.ProcessEnv = process.env, platform: NodeJS.Platform = process.platform): Paths {
  const home = env.HOME || env.USERPROFILE || os.homedir();
  let configDir: string;
  let dataDir: string;
  if (platform === 'win32') {
    const appData = env.APPDATA || path.join(home, 'AppData', 'Roaming');
    configDir = dataDir = path.join(appData, 'Patchdeck');
  } else {
    const xdg = (key: string, fallback: string) => (env[key] ? env[key]! : path.join(home, fallback));
    configDir = path.join(xdg('XDG_CONFIG_HOME', '.config'), 'patchdeck');
    dataDir = path.join(xdg('XDG_DATA_HOME', path.join('.local', 'share')), 'patchdeck');
  }
  return makePaths(env.PATCHDECK_CONFIG_DIR || configDir, env.PATCHDECK_DATA_DIR || dataDir);
}

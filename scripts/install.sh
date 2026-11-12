#!/usr/bin/env bash
# Patchdeck installer for Fedora / Ubuntu / Debian (and derivatives).
#
#   curl -fsSL https://raw.githubusercontent.com/horarodriguezz/patchdeck/main/scripts/install.sh | bash
#   ./scripts/install.sh              # per-user install into ~/.local (no root for the app itself)
#   ./scripts/install.sh --system     # system-wide into /usr/local (uses sudo)
#   ./scripts/install.sh --uninstall  # remove (add --system if installed system-wide)
#
# Options go after `bash -s --` when piping:  curl ... | bash -s -- --system
#
# Steps: installs build dependencies (dnf/apt, asks for sudo), installs Flutter
# locally if it is not on PATH, builds a release bundle and installs the
# binary, a launcher (.desktop) and the icon.
set -euo pipefail

# Everything runs inside main(), called on the last line: when piped from
# curl, bash has read the whole script before any command can touch stdin.
main() {

APP_ID="dev.patchdeck.patchdeck"
PREFIX="${HOME}/.local"
SUDO=""
AS_ROOT="sudo"; [[ ${EUID:-$(id -u)} -eq 0 ]] && AS_ROOT=""
SKIP_DEPS=0
UNINSTALL=0
FLUTTER_HOME="${PATCHDECK_FLUTTER_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/patchdeck-sdk/flutter}"
REPO_URL="https://github.com/horarodriguezz/patchdeck.git"
SRC_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/patchdeck-sdk/src"

usage() {
  cat <<'USAGE'
Uso: install.sh [--system] [--prefix DIR] [--skip-deps] [--uninstall]
  (sin opciones)  instala para tu usuario en ~/.local
  --system        instala para todo el sistema en /usr/local (sudo)
  --prefix DIR    instala en DIR
  --skip-deps     no instala paquetes del sistema
  --uninstall     desinstala (conserva reviews y configuración)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system) PREFIX="/usr/local"; SUDO="$AS_ROOT" ;;
    --prefix) PREFIX="$2"; shift ;;
    --skip-deps) SKIP_DEPS=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

APP_DIR="$PREFIX/lib/patchdeck"
BIN_DIR="$PREFIX/bin"
APPS_DIR="$PREFIX/share/applications"
ICON_ROOT="$PREFIX/share/icons/hicolor"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

refresh_caches() {
  command -v update-desktop-database >/dev/null && $SUDO update-desktop-database -q "$APPS_DIR" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null && $SUDO gtk-update-icon-cache -q -t -f "$ICON_ROOT" 2>/dev/null || true
}

if [[ $UNINSTALL -eq 1 ]]; then
  say "Desinstalando Patchdeck de $PREFIX"
  $SUDO rm -rf "$APP_DIR"
  $SUDO rm -f "$BIN_DIR/patchdeck" "$APPS_DIR/$APP_ID.desktop"
  $SUDO find "$ICON_ROOT" -name "$APP_ID.*" -delete 2>/dev/null || true
  refresh_caches
  say "Listo. Tus reviews y configuración siguen en ~/.local/share/patchdeck y ~/.config/patchdeck."
  exit 0
fi

# --- 0. Source tree -----------------------------------------------------------
# Run from a checkout: build that checkout. Piped from curl: keep a clone in
# $SRC_HOME and update it, so re-running the one-liner upgrades the app.
SRC=""
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  SRC="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
  [[ -f "$SRC/pubspec.yaml" ]] || SRC=""
fi
NEED_GIT=0
[[ -z "$SRC" ]] && NEED_GIT=1

# --- 1. System dependencies ---------------------------------------------------
if [[ $SKIP_DEPS -eq 0 ]]; then
  if command -v dnf >/dev/null 2>&1; then
    say "Instalando dependencias (dnf)"
    $AS_ROOT dnf install -y git curl unzip xz which tar clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel
  elif command -v apt-get >/dev/null 2>&1; then
    say "Instalando dependencias (apt)"
    $AS_ROOT apt-get update
    $AS_ROOT apt-get install -y git curl unzip xz-utils clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
  else
    warn "No encontré dnf ni apt-get: instala clang, cmake, ninja, pkg-config y GTK 3 (dev) y reintenta con --skip-deps."
    exit 1
  fi
fi

if [[ $NEED_GIT -eq 1 ]]; then
  command -v git >/dev/null || { warn "Hace falta git (o ejecuta sin --skip-deps)."; exit 1; }
  SRC="$SRC_HOME"
  if [[ -d "$SRC/.git" ]]; then
    say "Actualizando el código en $SRC"
    git -C "$SRC" fetch --depth 1 origin main
    git -C "$SRC" reset --hard -q origin/main
  else
    say "Descargando el código en $SRC"
    mkdir -p "$(dirname "$SRC")"
    git clone --depth 1 "$REPO_URL" "$SRC"
  fi
fi
cd "$SRC"

# --- 2. Flutter ---------------------------------------------------------------
if command -v flutter >/dev/null 2>&1; then
  FLUTTER="$(command -v flutter)"
elif [[ -x "$FLUTTER_HOME/bin/flutter" ]]; then
  FLUTTER="$FLUTTER_HOME/bin/flutter"
else
  say "Flutter no está instalado: descargándolo en $FLUTTER_HOME (sólo para compilar)"
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  FLUTTER="$FLUTTER_HOME/bin/flutter"
fi
"$FLUTTER" config --no-analytics >/dev/null 2>&1 || true
"$FLUTTER" config --enable-linux-desktop >/dev/null 2>&1 || true

# --- 3. Build -----------------------------------------------------------------
say "Compilando (release)"
"$FLUTTER" pub get
"$FLUTTER" build linux --release
ARCH_DIR="$(ls -d build/linux/*/release/bundle | head -1)"
[[ -x "$ARCH_DIR/patchdeck" ]] || { warn "No se generó el binario"; exit 1; }

# --- 4. Install ---------------------------------------------------------------
say "Instalando en $PREFIX"
$SUDO rm -rf "$APP_DIR"
$SUDO mkdir -p "$APP_DIR" "$BIN_DIR" "$APPS_DIR" "$ICON_ROOT/scalable/apps"
$SUDO cp -r "$ARCH_DIR/." "$APP_DIR/"
$SUDO ln -sf "$APP_DIR/patchdeck" "$BIN_DIR/patchdeck"

sed "s|@BINDIR@|$APP_DIR|" linux/packaging/$APP_ID.desktop | $SUDO tee "$APPS_DIR/$APP_ID.desktop" >/dev/null
$SUDO cp linux/packaging/$APP_ID.svg "$ICON_ROOT/scalable/apps/$APP_ID.svg"

# PNG sizes for launchers that don't render SVG (optional).
if command -v rsvg-convert >/dev/null 2>&1; then
  for s in 48 64 128 256 512; do
    $SUDO mkdir -p "$ICON_ROOT/${s}x${s}/apps"
    rsvg-convert -w $s -h $s linux/packaging/$APP_ID.svg | $SUDO tee "$ICON_ROOT/${s}x${s}/apps/$APP_ID.png" >/dev/null
  done
fi
refresh_caches

say "¡Instalado! Búscalo como «Patchdeck» en el menú de aplicaciones."
case ":$PATH:" in
  *":$BIN_DIR:"*) say "También puedes ejecutar: patchdeck" ;;
  *) warn "$BIN_DIR no está en tu PATH; agrégalo para lanzar 'patchdeck' desde la terminal." ;;
esac
}

main "$@"

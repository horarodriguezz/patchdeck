#!/usr/bin/env bash
# Installs the native toolchain Flutter needs to build Linux desktop apps.
set -euo pipefail

if command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel git curl unzip xz which
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev git curl unzip xz-utils
else
  echo "Distribución no soportada: instala clang, cmake, ninja, pkg-config y GTK3 (dev) manualmente." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  cat <<'MSG'

Flutter no está en el PATH. Instálalo (no requiere root):

  git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/.local/flutter
  export PATH="$HOME/.local/flutter/bin:$PATH"   # agrégalo a tu ~/.bashrc

MSG
fi

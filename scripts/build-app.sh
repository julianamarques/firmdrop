#!/bin/bash
# Compila em modo release e monta build/FirmDrop.app (assinatura ad-hoc, para uso local).
#   scripts/build-app.sh              → Apple Silicon (arm64)
#   scripts/build-app.sh --universal  → arm64 + Intel
#   scripts/build-app.sh --install    → também copia para /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
    --install) INSTALL=1 ;;
    *) echo "opção desconhecida: $arg" >&2; exit 1 ;;
  esac
done

swift build -c release --product FirmDrop ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR=$(swift build -c release --show-bin-path ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})

[ -f Resources/AppIcon.icns ] || scripts/make-icon.sh

APP=build/FirmDrop.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FirmDrop" "$APP/Contents/MacOS/FirmDrop"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE NOTICE Resources/licenses/Bifrost-LICENSE.txt "$APP/Contents/Resources/"
codesign --force --options runtime --sign - "$APP"

echo "Pronto: $APP"
if [ "$INSTALL" = 1 ]; then
  rm -rf /Applications/FirmDrop.app
  cp -R "$APP" /Applications/
  echo "Instalado em /Applications/FirmDrop.app"
fi

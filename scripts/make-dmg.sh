#!/bin/bash
# Gera build/FirmDrop.dmg com o app e um atalho para Aplicativos.
# Repassa as opções ao build-app.sh (ex.: --universal).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/FirmDrop.app"
DMG="build/FirmDrop.dmg"
STAGE="build/dmg"

scripts/build-app.sh "$@"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Aplicativos"
hdiutil create -quiet -volname "FirmDrop" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "Pronto: $DMG"

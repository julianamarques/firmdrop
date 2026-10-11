#!/usr/bin/env bash
# Baixa o adb do Android SDK Platform-Tools (versão fixa) para build/adb/, conferindo o SHA-256.
# O build-app.sh o embute no app junto com o NOTICE do Platform-Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="37.0.1"
SHA256="ee39ad5967e95c2a07f04dbcbde96b1a0c916ba376096db5d2f498b7727a5d1d"
OUTPUT="build/adb"

if [ -x "$OUTPUT/adb" ] && [ -f "$OUTPUT/adb-NOTICE.txt" ] && [ "$(cat "$OUTPUT/adb.version" 2>/dev/null)" = "$VERSION" ]; then
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -sSfL -o "$WORK/platform-tools.zip" "https://dl.google.com/android/repository/platform-tools_r$VERSION-darwin.zip"
echo "$SHA256  $WORK/platform-tools.zip" | shasum -a 256 -c --status || { echo "Checksum inválido para o Platform-Tools" >&2; exit 1; }
unzip -q -o "$WORK/platform-tools.zip" platform-tools/adb platform-tools/NOTICE.txt -d "$WORK"
mkdir -p "$OUTPUT"
mv "$WORK/platform-tools/adb" "$OUTPUT/adb"
mv "$WORK/platform-tools/NOTICE.txt" "$OUTPUT/adb-NOTICE.txt"
echo "$VERSION" > "$OUTPUT/adb.version"

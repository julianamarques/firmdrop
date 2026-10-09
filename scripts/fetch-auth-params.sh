#!/usr/bin/env bash
# Baixa o auth_param.dat do Bifrost (commit fixo) para Resources/, conferindo o SHA-256
# definido em Sources/FirmDropCore/Authenticator.swift. O build-app.sh o embute no app.
set -euo pipefail
cd "$(dirname "$0")/.."

COMMIT="ed73a034d3b27d84c68b2c21622a9de6618455de"
URL="https://raw.githubusercontent.com/zacharee/SamloaderKotlin/$COMMIT/common/src/commonMain/composeResources/files/auth_param.dat"
SHA256="$(sed -n 's/.*static let paramsSHA256 = "\([0-9a-f]*\)"/\1/p' Sources/FirmDropCore/Authenticator.swift)"
TARGET="Resources/auth_param.dat"

[ -n "$SHA256" ] || { echo "SHA-256 do auth_param.dat não encontrado em Authenticator.swift" >&2; exit 1; }

if [ -f "$TARGET" ] && echo "$SHA256  $TARGET" | shasum -a 256 -c --status; then
    exit 0
fi

curl -sSfL -o "$TARGET.download" "$URL"
echo "$SHA256  $TARGET.download" | shasum -a 256 -c --status || { rm -f "$TARGET.download"; echo "Checksum inválido para o auth_param.dat" >&2; exit 1; }
mv "$TARGET.download" "$TARGET"

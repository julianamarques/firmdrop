#!/usr/bin/env bash
# Extrai os textos traduzíveis do código e atualiza Resources/Localizable.xcstrings.
# Rode depois de adicionar ou alterar textos; os novos aparecem sem tradução no catálogo.
set -euo pipefail
cd "$(dirname "$0")/.."

CATALOG="Resources/Localizable.xcstrings"
SCRATCH=".build/strings"

[ -f "$CATALOG" ] || echo '{"sourceLanguage":"pt-BR","strings":{},"version":"1.0"}' > "$CATALOG"
rm -rf "$SCRATCH"
swift build --scratch-path "$SCRATCH" -Xswiftc -emit-localized-strings >/dev/null
find "$SCRATCH" -name '*.stringsdata' -print0 | xargs -0 xcrun xcstringstool sync "$CATALOG" --stringsdata
echo "Pronto: $CATALOG ($(xcrun xcstringstool print "$CATALOG" | wc -l | tr -d ' ') textos)"

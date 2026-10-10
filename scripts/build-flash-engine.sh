#!/bin/bash
# Builds a separate GPL-3.0-or-later process. Never links Brokkr into FirmDrop.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SOURCES="$ROOT/.build/flash-engine/sources"
OUTPUT="$ROOT/build/flash-engine"
mkdir -p "$SOURCES" "$OUTPUT"

fetch() {
  local name="$1" repo="$2" revision="$3"
  if [ ! -d "$SOURCES/$name/.git" ]; then
    git init -q "$SOURCES/$name"
  fi
  if ! git -C "$SOURCES/$name" cat-file -e "$revision^{commit}" 2>/dev/null; then
    git -C "$SOURCES/$name" fetch --depth 1 "$repo" "$revision"
  fi
  git -C "$SOURCES/$name" checkout -q --detach "$revision"
  # Refuse locally modified dependency code; the source bundle must match the build.
  test -z "$(git -C "$SOURCES/$name" status --porcelain)"
}
fetch brokkr https://github.com/Gabriel2392/brokkr-flash.git f7ae23067b4ee6c2e0211a1dee563f4be991cb4d
fetch spdlog https://github.com/gabime/spdlog.git 79524ddd08a4ec981b7fea76afd08ee05f83755d
fetch fmt https://github.com/fmtlib/fmt.git 407c905e45ad75fc29bf0f9bb7c5c2fd3475976f
fetch function2 https://github.com/Naios/function2.git 2d3a878ef19dd5d2fb188898513610fac0a48621

bash Engine/build.sh "$SOURCES" "$OUTPUT" "${1:-}"
cp "$SOURCES/brokkr/LICENSE" "$OUTPUT/Brokkr-LICENSE.txt"
cp "$SOURCES/brokkr/THIRD_PARTY_NOTICES.txt" "$OUTPUT/Brokkr-NOTICES.txt"
mkdir -p "$SOURCES/adapter"
cp Engine/main.cpp Engine/compat.hpp Engine/build.sh Engine/strict-mapping.patch Engine/resume-session.patch Engine/macos-sdk.patch Engine/README.md Engine/LICENSE "$SOURCES/adapter/"
# Include complete corresponding sources and build instructions with every binary.
COPYFILE_DISABLE=1 tar --exclude=.git -czf "$OUTPUT/flash-engine-source.tar.gz" \
  -C "$SOURCES" brokkr spdlog fmt function2 adapter
echo "Pronto: $OUTPUT/firmdrop-flash"

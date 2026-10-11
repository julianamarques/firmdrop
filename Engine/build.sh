#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Usage: bash adapter/build.sh SOURCE_DIRECTORY OUTPUT_DIRECTORY [--universal]
set -euo pipefail
SOURCES=$(cd "$1" && pwd)
mkdir -p "$2"
OUTPUT=$(cd "$2" && pwd)
ADAPTER=$(cd "$(dirname "$0")" && pwd)
ARCHES=("$(uname -m)")
if [ "${3:-}" = --universal ]; then ARCHES=(arm64 x86_64); fi

# Work on a copy; retain the pristine sources for the source distribution.
mkdir -p "$OUTPUT/patched"
cp "$SOURCES/brokkr/src/protocol/odin/group_flasher.cpp" "$OUTPUT/patched/group_flasher.cpp"
patch -s "$OUTPUT/patched/group_flasher.cpp" "$ADAPTER/strict-mapping.patch"
patch -s "$OUTPUT/patched/group_flasher.cpp" "$ADAPTER/resume-session.patch"
cp "$SOURCES/brokkr/src/protocol/odin/flash.cpp" "$OUTPUT/patched/flash.cpp"
patch -s "$OUTPUT/patched/flash.cpp" "$ADAPTER/download-list.patch"
cp "$SOURCES/brokkr/src/platform/macos/sysfs_usb.cpp" "$OUTPUT/patched/sysfs_usb.cpp"
patch -s "$OUTPUT/patched/sysfs_usb.cpp" "$ADAPTER/macos-sdk.patch"
FILES=(
  core/thread_pool.cpp io/random_access.cpp io/tar.cpp io/source.cpp io/lz4_frame.cpp
  protocol/odin/odin_cmd.cpp protocol/odin/pit.cpp
  protocol/odin/pit_transfer.cpp app/md5_xxh3_cache.cpp app/md5_verify.cpp
  platform/posix-common/app_dirs.cpp platform/posix-common/signal_shield.cpp
  platform/posix-common/single_instance.cpp
  platform/macos/usbfs_device.cpp platform/macos/usbfs_conn.cpp
)
for ARCH in "${ARCHES[@]}"; do
  OBJECTS="$OUTPUT/$ARCH"
  mkdir -p "$OBJECTS"
  FLAGS=(-arch "$ARCH" -mmacosx-version-min=26.0 -O2 -DNDEBUG -DBROKKR_PLATFORM_MACOS
    -I "$SOURCES/brokkr/src" -isystem "$SOURCES/spdlog/include" -isystem "$SOURCES/fmt/include"
    -isystem "$SOURCES/function2/include")
  xcrun clang "${FLAGS[@]}" -c "$SOURCES/brokkr/src/third_party/lz4/lz4.c" -o "$OBJECTS/lz4.o"
  xcrun clang "${FLAGS[@]}" -c "$SOURCES/brokkr/src/third_party/md5/md5.c" -o "$OBJECTS/md5.o"
  CPP_FILES=()
  for FILE in "${FILES[@]}"; do CPP_FILES+=("$SOURCES/brokkr/src/$FILE"); done
  xcrun clang++ "${FLAGS[@]}" -std=c++23 -pthread -DFMT_HEADER_ONLY \
    -include "$ADAPTER/compat.hpp" "${CPP_FILES[@]}" "$OUTPUT/patched/group_flasher.cpp" "$OUTPUT/patched/flash.cpp" \
    "$OUTPUT/patched/sysfs_usb.cpp" \
    "$ADAPTER/main.cpp" "$OBJECTS/lz4.o" "$OBJECTS/md5.o" \
    -framework IOKit -framework CoreFoundation -o "$OBJECTS/firmdrop-flash"
done
if [ "${#ARCHES[@]}" = 2 ]; then
  lipo -create "$OUTPUT/arm64/firmdrop-flash" "$OUTPUT/x86_64/firmdrop-flash" -output "$OUTPUT/firmdrop-flash"
else
  cp "$OUTPUT/${ARCHES[0]}/firmdrop-flash" "$OUTPUT/firmdrop-flash"
fi
codesign --force --options runtime --sign - "$OUTPUT/firmdrop-flash"

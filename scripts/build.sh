#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
CMAKE="$PWD/.tools/python/bin/cmake"
if [ ! -x "$CMAKE" ] || [ ! -d vendor/cef ] || [ ! -d vendor/sparkle/Sparkle.framework ]; then
  python3 scripts/bootstrap.py
fi
python3 scripts/bootstrap_import.py
"$CMAKE" -S . -B build -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=arm64
"$CMAKE" --build build -j 8
"$PWD/.tools/python/bin/ctest" --test-dir build --output-on-failure
python3 scripts/package.py

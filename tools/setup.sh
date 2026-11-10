#!/bin/bash
# setup.sh: everything from a fresh clone to Dark Souls in /Applications.
#   tools/setup.sh [/path/to/game]     (the folder with DATA/; asked if omitted)
# Installs the Homebrew packages, builds the lifter, lifts your DATA.exe,
# compiles the game (the first time takes a long while) and installs the app.
# Safe to re-run: each step only redoes what changed.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"

[ "$(uname -sm)" = "Darwin arm64" ] || { echo "setup.sh: needs macOS on Apple silicon"; exit 1; }
xcode-select -p >/dev/null 2>&1 || { echo "setup.sh: install the command line tools first: xcode-select --install"; exit 1; }
command -v brew >/dev/null || { echo "setup.sh: install Homebrew first: https://brew.sh"; exit 1; }
[ -f vendor/x86recomp/CMakeLists.txt ] || git submodule update --init --recursive

pkgs=(cmake ninja llvm@22 sdl3 ffmpeg glslang spirv-cross pkgconf upx python)
missing=()
for p in "${pkgs[@]}"; do brew list --formula "$p" >/dev/null 2>&1 || missing+=("$p"); done
[ ${#missing[@]} -eq 0 ] || brew install "${missing[@]}"

if [ -n "${1-}" ]; then
  echo "DARKSOULS_GAME_DIR=$(printf '%q' "$(cd "$1" && pwd)")" > tools/local.env
elif [ ! -f tools/local.env ]; then
  read -r -p "Dark Souls folder (the one with DATA/ inside; you can drag it here): " dir
  dir=${dir%/}; dir=${dir//\\ / }
  echo "DARKSOULS_GAME_DIR=$(printf '%q' "$(cd "$dir" && pwd)")" > tools/local.env
fi
. tools/local.env
[ -f "$DARKSOULS_GAME_DIR/DATA/DATA.exe" ] || { echo "setup.sh: no DATA/DATA.exe in $DARKSOULS_GAME_DIR"; rm -f tools/local.env; exit 1; }

[ -f out/build/release/build.ninja ] || cmake --preset release
cmake --build out/build/release --target recomp_lift
tools/lift.sh
echo "setup.sh: compiling the game; the first build takes a while (progress: tail -f logs/build-*.out)"
tools/build.sh
tools/app.sh --install
echo "setup.sh: done. Start Dark Souls from Applications or Spotlight."

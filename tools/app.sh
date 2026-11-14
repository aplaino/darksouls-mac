#!/bin/bash
# app.sh: makes out/DarkSouls.app, a self-contained bundle of the built game
# (binary and runtime libraries inside, the game folder and the unpacked
# fmodex.dll in Resources). With --install it is copied to /Applications,
# where Spotlight, Launchpad and the Dock find it.
#   tools/app.sh [--install] && open out/DarkSouls.app
#   open --env DARKSOULS_TRACE=1 -a "DarkSouls"     (switches as with run.sh)
#   tools/app.sh --kit BUILD_DIR DEPS_PREFIX OUT.app
#     the Builder's bundle (builder/make_builder.sh): no executable, game
#     folder or fmodex.dll, which the Builder adds; the libraries from
#     DEPS_PREFIX go into Frameworks too.
# Launched through LaunchServices (open, Finder, the Dock), macOS lets the
# game take keyboard focus; started in the background from a terminal, it
# leaves the keyboard with the terminal. Logs go to ~/Library/Logs/DarkSouls.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
kit=
if [ "${1-}" = "--kit" ]; then
  kit=1 build=$2 deps=$3 app=$4
else
  [ -f "$here/tools/local.env" ] && . "$here/tools/local.env"
  : "${DARKSOULS_GAME_DIR:?set DARKSOULS_GAME_DIR (tools/local.env) to the folder with DATA/}"
  game_dir=$(cd "$DARKSOULS_GAME_DIR" && pwd)
  build="$here/out/build/release"
  deps=
  app="$here/out/DarkSouls.app"
fi
bin="$build/darksouls"
[ -n "$kit" ] || [ -x "$bin" ] || { echo "app.sh: build first (tools/build.sh): no $bin"; exit 1; }

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DarkSouls</string>
  <key>CFBundleIdentifier</key><string>local.darksouls-mac</string>
  <key>CFBundleName</key><string>Dark Souls</string>
  <key>CFBundleDisplayName</key><string>Dark Souls</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# The binary finds its runtime libraries through an rpath into the build
# tree; inside the bundle they sit in Frameworks/, with every library they
# load through @rpath (in the kit, SDL3 and FFmpeg from DEPS_PREFIX; in the
# Terminal build Homebrew's stay where Homebrew put them). cp -c clones on
# APFS (no extra space).
fw="$app/Contents/Frameworks"
rpath_deps() { otool -L "$1" | awk 'NR > 1 && $1 ~ /^@rpath\// {sub("@rpath/", "", $1); print $1}'; }
add_lib() {
  [ -f "$fw/$1" ] && return
  local from
  for d in "$build/x86recomp" ${deps:+"$deps/lib"}; do
    [ -f "$d/$1" ] && from=$d/$1 && break
  done
  [ -n "${from-}" ] || { echo "app.sh: no $1"; exit 1; }
  cp -cL "$from" "$fw/$1"
  local dep
  for dep in $(rpath_deps "$fw/$1"); do add_lib "$dep"; done
}
if [ -n "$kit" ]; then
  for t in runtime d3d9 dinput8 xinput xlive dsound; do add_lib "librecomp_$t.dylib"; done
else
  cp -c "$bin" "$app/Contents/MacOS/game"
  for dep in $(rpath_deps "$bin"); do add_lib "$dep"; done
  install_name_tool -rpath "$build/x86recomp" "@executable_path/../Frameworks" "$app/Contents/MacOS/game" 2>/dev/null
  printf '%s' "$game_dir" > "$app/Contents/Resources/game-dir"
  cp -c "$here/work/lift/fmodex.dll" "$app/Contents/Resources/fmodex.dll"
fi
# No run paths of the machine that built it.
for lib in "$fw"/*.dylib; do
  for rp in $(otool -l "$lib" | awk '/cmd LC_RPATH/ {r = 1} r && $1 == "path" {print $2; r = 0}'); do
    case $rp in @*) ;; *) install_name_tool -delete_rpath "$rp" "$lib" ;; esac
  done
done
[ -n "$kit" ] || codesign --force -s - "$fw"/*.dylib "$app/Contents/MacOS/game" 2>/dev/null

cat > "$app/Contents/MacOS/DarkSouls" <<EOF
#!/bin/bash
contents=\$(cd "\$(dirname "\$0")/.." && pwd)
game_dir=\$(cat "\$contents/Resources/game-dir")
# Graphics (the game plays the same; open --env NAME=value overrides each):
# the 3D scene's 1024x720 targets (and their halves) 3x larger, the shadow
# map 2x, SMAA on the finished frame, 16x anisotropic filtering, and the
# Metal performance HUD (fps, frame time, GPU time) in the top-right corner.
export RECOMP_RT_BOOST="\${RECOMP_RT_BOOST-1024x720:3,512x360:3,256x180:3,2048x2048:2}"
export RECOMP_UPSCALER="\${RECOMP_UPSCALER-smaa}"
export DARKSOULS_ANISO="\${DARKSOULS_ANISO-16}"
export MTL_HUD_ENABLED="\${MTL_HUD_ENABLED-1}"
logs="\$HOME/Library/Logs/DarkSouls"
mkdir -p "\$logs"
if [ ! -f "\$game_dir/DATA/DATA.exe" ]; then
  osascript -e "display alert \"Dark Souls\" message \"The game files are not at \$game_dir. Build the app again with the game's new folder.\""
  exit 1
fi
exec "\$contents/MacOS/game" --game-dir "\$game_dir" --fmodex "\$contents/Resources/fmodex.dll" "\$@" > "\$logs/run-\$(date +%Y%m%d-%H%M%S).log" 2>&1
EOF
chmod +x "$app/Contents/MacOS/DarkSouls"
echo "app.sh: $app"

if [ -z "$kit" ] && [ "${1-}" = "--install" ]; then
  rm -rf "/Applications/DarkSouls.app"
  cp -cR "$app" /Applications/
  echo "app.sh: installed /Applications/DarkSouls.app"
fi

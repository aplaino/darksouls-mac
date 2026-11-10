#!/bin/bash
# app.sh: makes out/DarkSouls.app, a self-contained bundle of the built game
# (binary and runtime libraries inside; the game folder from tools/local.env
# is written into its launcher). With --install it is copied to
# /Applications, where Spotlight, Launchpad and the Dock find it.
#   tools/app.sh [--install] && open out/DarkSouls.app
#   open --env DARKSOULS_TRACE=1 -a "Dark Souls"     (switches as with run.sh)
# Launched through LaunchServices (open, Finder, the Dock), macOS lets the
# game take keyboard focus; started in the background from a terminal, it
# leaves the keyboard with the terminal. Logs go to ~/Library/Logs/DarkSouls.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$here/tools/local.env" ] && . "$here/tools/local.env"
: "${DARKSOULS_GAME_DIR:?set DARKSOULS_GAME_DIR (tools/local.env) to the folder with DATA/}"
game_dir=$(cd "$DARKSOULS_GAME_DIR" && pwd)
build="$here/out/build/release"
bin="$build/darksouls"
[ -x "$bin" ] || { echo "app.sh: build first (tools/build.sh): no $bin"; exit 1; }

app="$here/out/DarkSouls.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
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
# tree; inside the bundle they sit in Frameworks/. Homebrew's SDL3 and
# FFmpeg stay where Homebrew put them. cp -c clones on APFS (no extra space).
cp -c "$bin" "$app/Contents/MacOS/game"
for lib in $(otool -L "$bin" | awk '/@rpath\/librecomp_/ {sub("@rpath/", "", $1); print $1}'); do
  cp -c "$build/x86recomp/$lib" "$app/Contents/Frameworks/"
done
for lib in "$app/Contents/Frameworks"/*.dylib; do
  for dep in $(otool -L "$lib" | awk '/@rpath\/librecomp_/ {sub("@rpath/", "", $1); print $1}'); do
    [ -f "$app/Contents/Frameworks/$dep" ] || cp -c "$build/x86recomp/$dep" "$app/Contents/Frameworks/"
  done
done
install_name_tool -rpath "$build/x86recomp" "@executable_path/../Frameworks" "$app/Contents/MacOS/game" 2>/dev/null
codesign --force -s - "$app/Contents/Frameworks"/*.dylib "$app/Contents/MacOS/game" 2>/dev/null

cat > "$app/Contents/MacOS/DarkSouls" <<EOF
#!/bin/bash
contents=\$(cd "\$(dirname "\$0")/.." && pwd)
game_dir=$(printf '%q' "$game_dir")
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
  osascript -e "display alert \"Dark Souls\" message \"The game files are not at \$game_dir. Point tools/local.env at them and run tools/app.sh again.\""
  exit 1
fi
exec "\$contents/MacOS/game" --game-dir "\$game_dir" "\$@" > "\$logs/run-\$(date +%Y%m%d-%H%M%S).log" 2>&1
EOF
chmod +x "$app/Contents/MacOS/DarkSouls"
echo "app.sh: $app"

if [ "${1-}" = "--install" ]; then
  rm -rf "/Applications/DarkSouls.app"
  cp -cR "$app" /Applications/
  echo "app.sh: installed /Applications/DarkSouls.app"
fi

#!/bin/bash
# app.sh: (re)makes out/DarkSouls.app, a bundle that starts the built game.
# Launched through LaunchServices (open, Finder, the Dock), macOS lets the
# game take keyboard focus; started in the background from a terminal, it
# leaves the keyboard with the terminal.
#   tools/app.sh && open out/DarkSouls.app
#   open --env DARKSOULS_TRACE=1 out/DarkSouls.app     (switches as with run.sh)
# The launcher execs the game (so it is the app's own process) and logs to
# logs/run-<time>.log.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
app="$here/out/DarkSouls.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DarkSouls</string>
  <key>CFBundleIdentifier</key><string>local.ds-recomp.darksouls</string>
  <key>CFBundleName</key><string>Dark Souls</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
cat > "$app/Contents/MacOS/DarkSouls" <<EOF
#!/bin/bash
here="$here"
[ -f "\$here/tools/local.env" ] && . "\$here/tools/local.env"
# Graphics (the game plays the same; open --env NAME=value overrides each):
# the 3D scene's 1024x720 targets (and their halves) 3x larger, the shadow
# map 2x, SMAA on the finished frame, 16x anisotropic filtering, and the
# Metal performance HUD (fps, frame time, GPU time) in the top-right corner.
export RECOMP_RT_BOOST="\${RECOMP_RT_BOOST-1024x720:3,512x360:3,256x180:3,2048x2048:2}"
export RECOMP_UPSCALER="\${RECOMP_UPSCALER-smaa}"
export DARKSOULS_ANISO="\${DARKSOULS_ANISO-16}"
export MTL_HUD_ENABLED="\${MTL_HUD_ENABLED-1}"
mkdir -p "\$here/logs"
exec "\$here/out/build/release/darksouls" --game-dir "\$DARKSOULS_GAME_DIR" "\$@" \\
  > "\$here/logs/run-\$(date +%H%M%S).log" 2>&1
EOF
chmod +x "$app/Contents/MacOS/DarkSouls"
echo "app.sh: $app"

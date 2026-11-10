#!/bin/bash
# lift.sh: the game's code, from your own DATA.exe (1.0.2.0), translated to
# C++ in generated/: the lifted executable (recomp_lift, with the symbols in
# symbols/ and this port's changes in manifest/darksouls.manifest) plus the
# two FMOD DLLs the game loads itself (lifted as modules, so their code is
# native too instead of being reimplemented in the HLE).
# Run it after the first build (which makes the lifter) and again after
# changing a manifest; then build again.
#   DARKSOULS_GAME_DIR: the game's folder (the one with DATA/), from the
#   environment or tools/local.env.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$here/tools/local.env" ] && . "$here/tools/local.env"
: "${DARKSOULS_GAME_DIR:?set DARKSOULS_GAME_DIR to the folder with DATA/}"
exe="$DARKSOULS_GAME_DIR/DATA/DATA.exe"
[ -f "$exe" ] || { echo "no DATA/DATA.exe in $DARKSOULS_GAME_DIR"; exit 1; }
want=44d2dccb1d522f8a320784381ecf83aeb62643d0fc38ae2f4ddf3ca066b52b6c
have=$(shasum -a 256 "$exe" | cut -d' ' -f1)
[ "$have" = "$want" ] || { echo "DATA.exe is not version 1.0.2.0 (SHA-256 $have, want $want)"; exit 1; }
lift="${LIFTER:-$here/out/build/release/x86recomp/tools/lifter/recomp_lift}"
[ -x "$lift" ] || { echo "build first (cmake --preset release && cmake --build --preset release): no $lift"; exit 1; }

mods=()
for m in fmodex fmod_event; do
  [ -d "$here/symbols/$m" ] || continue
  base=()
  [ "$m" = "fmod_event" ] && base=(--base 11000000)
  mods+=(--module "$m.dll" --symbols "$here/symbols/$m"
         --manifest "$here/manifest/$m.manifest" ${base[@]+"${base[@]}"})
done

# The lifter reads the modules by file name from its working directory, so
# it runs in work/lift/: DATA.exe and fmod_event.dll are links into the game
# tree, and fmodex.dll is the unpacked copy. The shipped fmodex.dll is
# UPX-packed; the runtime maps that image at the lifted module's base and
# executes the lifted code, so the install holds the unpacked image too
# (identical VAs). The original packed file is kept as
# work/lift/fmodex.upx.dll.
mkdir -p "$here/work/lift"
ln -sf "$DARKSOULS_GAME_DIR/DATA/DATA.exe" "$here/work/lift/DATA.exe"
ln -sf "$DARKSOULS_GAME_DIR/DATA/fmod_event.dll" "$here/work/lift/fmod_event.dll"
[ -f "$here/work/lift/fmodex.dll" ] || cp "$DARKSOULS_GAME_DIR/DATA/fmodex.dll" "$here/work/lift/fmodex.dll"
if grep -aqi upx0 "$here/work/lift/fmodex.dll"; then
  upx -d -f -q "$here/work/lift/fmodex.dll" || { echo "upx -d failed on fmodex.dll"; exit 1; }
fi

echo "lift.sh: lifting DATA.exe"
(cd "$here/work/lift" && "$lift" --exe DATA.exe --symbols "$here/symbols/darksouls" \
  --manifest "$here/manifest/darksouls.manifest" --out "$here/generated" "${mods[@]}" "$@")
echo "lift.sh: done"

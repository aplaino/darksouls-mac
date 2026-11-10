#!/bin/bash
# run.sh: start the game, logging to logs/run-<time>.log.
#   tools/run.sh [extra args]        DARKSOULS_TRACE=1 tools/run.sh   (verbose HLE)
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$here/tools/local.env" ] && . "$here/tools/local.env"
: "${DARKSOULS_GAME_DIR:?set DARKSOULS_GAME_DIR to the folder with DATA/}"
bin="$here/out/build/release/darksouls"
[ -x "$bin" ] || { echo "no binary: $bin (build first)"; exit 1; }
mkdir -p "$here/logs"
log="$here/logs/run-$(date +%H%M%S).log"
echo "darksouls: logging to $log"
"$bin" --game-dir "$DARKSOULS_GAME_DIR" "$@" 2>&1 | tee "$log"

#!/bin/sh
# ghidra_export.sh: function and jump-table export of the game's modules from
# the auto-analysed Ghidra projects in ghidra/, into
# symbols/<module>/{functions,jumptables}.tsv. Read only: the analysis is done
# once by ghidra_analyze.sh, and re-running this after changing nothing else
# is cheap.
#   usage: tools/ghidra_export.sh [darksouls fmodex fmod_event]
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$R/tools/local.env" ] && . "$R/tools/local.env"
: "${DARKSOULS_GAME_DIR:?set DARKSOULS_GAME_DIR to the folder with DATA/}"
H=/opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless
S=$R/vendor/x86recomp/tools/ghidra
export GHIDRA_HEADLESS_MAXMEM=${GHIDRA_HEADLESS_MAXMEM:-24G}
export OBJDUMP=${OBJDUMP:-/opt/homebrew/opt/llvm@22/bin/llvm-objdump}

export_one() {
  project=$1 prog=$2 mod=$3
  mkdir -p "$R/symbols/$mod" "$R/logs"
  echo "== export $mod ($prog) $(date +%T)"
  "$H" "$R/ghidra" "$project" -process "$prog" \
    -noanalysis -readOnly -scriptPath "$S" \
    -postScript ExportFunctions.java "$R/symbols/$mod/functions.tsv" \
    -postScript ExportJumpTables.java "$R/symbols/$mod/jumptables.tsv" \
    -log "$R/logs/ghidra-$mod.log" > "$R/logs/ghidra-$mod.out" 2>&1
  echo "rc=$? $(grep -h -E "ExportFunctions:|ExportJumpTables:" "$R/logs/ghidra-$mod.out" | tr "\n" " ")"
  # Switch tables Ghidra left without targets, read from the image.
  rm -f "$R/symbols/$mod/jumptables.tsv.ghidra"
  exe="$R/$4"
  python3 -I "$R/tools/complete_jumptables.py" "$exe" "$R/symbols/$mod/jumptables.tsv" ||
    echo "warning: complete_jumptables failed for $mod"
}

[ $# -eq 0 ] && set -- darksouls
for m in "$@"; do
  case $m in
    darksouls) export_one ds-darksouls DATA.exe darksouls "$DARKSOULS_GAME_DIR/DATA/DATA.exe" ;;
    fmodex)    export_one ds-fmodex fmodex.dll fmodex "work/lift/fmodex.dll" ;;
    fmod_event) export_one ds-fmod_event fmod_event.dll fmod_event "$DARKSOULS_GAME_DIR/DATA/fmod_event.dll" ;;
    *) echo "unknown module $m"; exit 1 ;;
  esac
done

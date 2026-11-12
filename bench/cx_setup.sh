#!/bin/zsh
# Sets up the ds1bench CrossOver bottle the benchmarks compare against:
# the same game files (APFS clones of DARKSOULS_GAME_DIR, no extra space),
# GFWL answered by bench/xlive (the runtime's offline behaviour, as a DLL),
# msync on as CrossOver's app turns it on, the bottle's user folders kept
# inside it, and the game's ini set as the port runs it. Run again after
# the game's first start, which writes the ini.
set -e
cd ${0:a:h}
source ../tools/local.env
CX=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin
BOTTLE=~/Library/Application\ Support/CrossOver/Bottles/ds1bench
USERDIR=$BOTTLE/drive_c/users/crossover

[[ -d $BOTTLE ]] || $CX/cxbottle --bottle ds1bench --create --template win10_64
grep -q '^"WINEMSYNC"' $BOTTLE/cxbottle.conf ||
  sed -i '' 's/^\[EnvironmentVariables\]$/[EnvironmentVariables]\
"WINEMSYNC" = "1"/' $BOTTLE/cxbottle.conf

# CrossOver links these to the Mac's own folders; the game would save into
# ~/Documents.
for d in Documents Downloads Music Pictures Videos; do
  [[ -L $USERDIR/$d ]] && rm $USERDIR/$d && mkdir $USERDIR/$d
done
mkdir -p $USERDIR/Documents/NBGI/DarkSouls/Player

if [[ ! -d $BOTTLE/drive_c/DarkSouls/DATA ]]; then
  mkdir -p $BOTTLE/drive_c/DarkSouls
  cp -cR $DARKSOULS_GAME_DIR/DATA $BOTTLE/drive_c/DarkSouls/
fi

i686-w64-mingw32-gcc -O2 -shared -o xlive/xlive.dll xlive/xlive.c xlive/xlive.def \
  -lws2_32 -static-libgcc -Wl,--enable-stdcall-fixup
cp xlive/xlive.dll $BOTTLE/drive_c/windows/syswow64/
swiftc -O tools/key.swift -o tools/key
swiftc -O tools/winid.swift -o tools/winid

# As the port runs it: a 1600x900 window, the game's own AA off, the menu
# on Escape.
INI=$USERDIR/AppData/Local/NBGI/DarkSouls/DarkSouls.ini
if [[ -f $INI ]]; then
  LC_ALL=C sed -i '' -e '/^\[DisplaySettingWindow\]/,/^\[/{s/^Width=.*/Width=1600/;s/^Height=.*/Height=900/;}' \
    -e 's/^ForceDisableAA=.*/ForceDisableAA=1/' -e 's/^MenuDisp=.*/MenuDisp=27/' $INI
  echo "cx_setup: ready"
else
  echo "cx_setup: start the game once (bench/cx_run.sh), quit it, and run this again"
fi

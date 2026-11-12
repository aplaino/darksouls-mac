#!/bin/zsh
# Starts the game in the ds1bench CrossOver bottle, from its DATA folder,
# and waits for it to exit. CX_EXE (bench/local.env) names the executable
# that starts the game in your install; DATA.exe by default.
# CX_LOG / CX_DEBUG: CrossOver's --cx-log / --debugmsg.
[[ -f ${0:a:h}/local.env ]] && source ${0:a:h}/local.env
CX=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin
opts=()
[[ -n $CX_LOG ]] && opts+=(--cx-log $CX_LOG)
[[ -n $CX_DEBUG ]] && opts+=(--debugmsg $CX_DEBUG)
exec $CX/wine --bottle ds1bench $opts cmd /c "cd /d C:\\DarkSouls\\DATA && ${CX_EXE:-DATA.exe}"

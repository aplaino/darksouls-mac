#!/bin/bash
# build.sh: build the release preset, one build at a time.
#   tools/build.sh [cmake --build args]   logs to logs/build-<time>.out
# Two ninjas in one build dir corrupt .ninja_deps, which then forces a
# full rebuild of the lifted code every time; the lock prevents that.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$here/logs"
log="$here/logs/build-$(date +%H%M%S).out"
echo "build.sh: logging to $log"
/usr/bin/lockf -s -t 0 "$here/out/build/release/.build.lock" \
  cmake --build "$here/out/build/release" "$@" > "$log" 2>&1
status=$?
[ $status -eq 75 ] && echo "build.sh: another build is running in out/build/release" >&2
grep -E 'error|premature' "$log" | head -20
tail -1 "$log"
exit $status

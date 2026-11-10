#!/bin/bash
# triage.sh: what killed the last run — the newest crash report with guest
# addresses named, then the newest run log's fatal and last HLE calls.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
python3 "$here/tools/where.py" --crash
echo
python3 "$here/tools/where.py" --log

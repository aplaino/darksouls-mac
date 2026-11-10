#!/usr/bin/env python3
"""where.py: name guest addresses in this port.

  tools/where.py 00AE4C2C 00C64B91 ...   # addresses to function names
  tools/where.py --crash [FILE]          # newest crash report -> call chain
  tools/where.py --log [FILE]            # newest run log -> fatal + imports

The mapping is symbols/<module>/functions.tsv as exported from Ghidra, so it
covers every function the lifter saw, named or not (FUN_<va>).
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(os.path.dirname(__file__)))

# (low, high, path, base_delta): the VA ranges each module's lifted code
# covers. fmod_event is lifted at 0x11000000 but its symbols are at its
# preferred base 0x10000000.
MODULES = [
    (0x00400000, 0x02000000, "darksouls", 0),
    (0x10000000, 0x10200000, "fmodex", 0),
    (0x11000000, 0x11200000, "fmod_event", -0x1000000),
]

_cache = {}


def load(module):
    if module in _cache:
        return _cache[module]
    path = os.path.join(HERE, "symbols", module, "functions.tsv")
    funcs = []
    try:
        with open(path) as f:
            next(f)  # header
            for line in f:
                c = line.rstrip("\n").split("\t")
                if len(c) < 8:
                    continue
                funcs.append((int(c[0], 16), int(c[2], 16), c[7]))
    except FileNotFoundError:
        pass
    funcs.sort()
    _cache[module] = funcs
    return funcs


def module_for(va):
    for lo, hi, mod, delta in MODULES:
        if lo <= va < hi:
            return mod, va + delta
    return None, va


def name(va):
    mod, v = module_for(va)
    if not mod:
        return f"{va:08X}  <not in any module>"
    funcs = load(mod)
    best = None
    for entry, end, fname in funcs:
        if entry <= v:
            best = (entry, end, fname)
        else:
            break
    if not best or v > best[1]:
        return f"{va:08X}  <{mod}: no function>"
    entry, end, fname = best
    return f"{va:08X}  {mod}!{fname} +0x{v - entry:X}"


HEX = re.compile(r"\b([0-9A-Fa-f]{8})\b")


def newest(pattern):
    hits = sorted(glob.glob(pattern), key=os.path.getmtime)
    return hits[-1] if hits else None


def data_dir():
    x = os.environ.get("XDG_DATA_HOME")
    if x:
        return os.path.join(x, "darksouls")
    return os.path.join(os.path.expanduser("~"), "Library/Application Support/darksouls")


def crash(path):
    if not path:
        path = newest(os.path.join(data_dir(), "crashes", "*.txt"))
    if not path:
        print("no crash report yet")
        return 1
    print(f"== {path}")
    text = open(path, errors="replace").read()
    for line in text.splitlines():
        if "FATAL" in line or "fault" in line or "eip=" in line or line.strip().startswith("eax="):
            print(line)
    print("-- guest addresses in the report (stack = call chain, innermost first)")
    seen = set()
    for m in HEX.finditer(text):
        va = int(m.group(1), 16)
        mod, _ = module_for(va)
        if not mod or va in seen:
            continue
        seen.add(va)
        print("  " + name(va))
    return 0


def log(path):
    if not path:
        path = newest(os.path.join(HERE, "logs", "run-*.log"))
    if not path:
        print("no run log yet")
        return 1
    print(f"== {path}")
    lines = open(path, errors="replace").read().splitlines()
    fatal = [i for i, l in enumerate(lines) if "FATAL" in l]
    if fatal:
        print("-- fatal")
        for l in lines[fatal[0]:fatal[0] + 14]:
            print("  " + l)
    calls = [l for l in lines if re.search(r"hle:|-> [a-z0-9_]+\.dll!|import ", l)]
    print(f"-- last 25 HLE-looking lines (of {len(calls)})")
    for l in calls[-25:]:
        print("  " + l.strip()[:160])
    return 0


def main(argv):
    if argv and argv[0] in ("--crash", "--log"):
        fn = crash if argv[0] == "--crash" else log
        return fn(argv[1] if len(argv) > 1 else None)
    if not argv:
        print(__doc__)
        return 2
    for a in argv:
        va = int(a, 16) if a.lower().startswith("0x") else int(a, 16)
        print(name(va))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

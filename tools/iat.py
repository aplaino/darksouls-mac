#!/usr/bin/env python3
"""iat.py [VA ...] - map exe IAT slots (or addresses near them) to dll!name."""
import struct
import sys

import os

# The game's folder (the one with DATA/), as tools/run.sh takes it.
EXE = os.path.join(os.environ.get("DARKSOULS_GAME_DIR", "game"), "DATA", "DATA.exe")


def load():
    d = open(EXE, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    opt = pe + 24
    base = struct.unpack_from("<I", d, opt + 28)[0]
    secs = []
    for i in range(nsec):
        o = opt + struct.unpack_from("<H", d, pe + 20)[0] + 40 * i
        name = d[o:o + 8].rstrip(b"\0").decode()
        vs, va, rs, ra = struct.unpack_from("<IIII", d, o + 8)
        secs.append((name, va, vs, ra, rs))
    return d, base, secs


def rva_of(va, base, secs):
    rva = va - base
    for name, sva, vsz, raw, rsz in secs:
        if sva <= rva < sva + max(vsz, rsz):
            return raw + (rva - sva)
    return None


def main():
    d, base, secs = load()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    opt = pe + 24
    # data directory 1 = import table
    imp_rva, imp_size = struct.unpack_from("<II", d, opt + 96 + 8)
    off = rva_of(base + imp_rva, base, secs)
    table = {}
    while True:
        ilt, ts, fc, name_rva, iat = struct.unpack_from("<IIIII", d, off)
        if name_rva == 0:
            break
        no = rva_of(base + name_rva, base, secs)
        dll = d[no:d.index(b"\0", no)].decode()
        thunk = rva_of(base + (ilt or iat), base, secs)
        slot = base + iat
        while True:
            v = struct.unpack_from("<I", d, thunk)[0]
            if v == 0:
                break
            if v & 0x80000000:
                nm = "#%d" % (v & 0xFFFF)
            else:
                fo = rva_of(base + v, base, secs)
                nm = d[fo + 2:d.index(b"\0", fo + 2)].decode()
            table[slot] = "%s!%s" % (dll, nm)
            slot += 4
            thunk += 4
        off += 20
    for a in sys.argv[1:]:
        va = int(a, 16)
        best = None
        for slot in table:
            if slot <= va < slot + 4:
                best = slot
        print("%08X -> %s" % (va, table.get(best, "?")))


if __name__ == "__main__":
    main()

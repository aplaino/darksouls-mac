#!/usr/bin/env python3
"""Captures the game window in two fixed places, for comparing images.

  capture.py <port|crossover> <out dir>

<out>/<mode>-world.png: standing at the save's spawn, after loading.
<out>/<mode>-brightness.png: System > Brightness, the static flame and
dragon preview that goes through the game's gamma pass.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bench
ESC, RIGHT, DOWN, RETURN = 53, 124, 125, 36


def shot(pid, path):
    wid = subprocess.run([os.path.join(HERE, "tools/winid"), str(pid)],
                         capture_output=True, text=True).stdout.strip()
    subprocess.run(["screencapture", "-x", "-o", f"-l{wid}", path], check=True)


def main():
    mode, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    os.makedirs(bench.WORK, exist_ok=True)
    with open(os.path.join(bench.WORK, f"capture-{mode}.log"), "w") as log:
        t0 = time.time()
        p, _ = bench.launch(mode, log)
        presses = list(bench.PRESS_AT)
        while time.time() - t0 < bench.MEASURE_FROM:
            if presses and time.time() - t0 >= presses[0]:
                presses.pop(0)
                g = bench.game_pid(mode, p)
                if g:
                    bench.front(g)
                    subprocess.run([bench.KEY, str(g), str(RETURN), "100"])
            time.sleep(0.2)
        g = bench.game_pid(mode, p)
        bench.front(g)
        time.sleep(2)
        shot(g, os.path.join(out, f"{mode}-world.png"))
        for k, wait in ((ESC, 3), (RIGHT, 1), (RIGHT, 1), (RIGHT, 1), (RETURN, 2), (DOWN, 1), (RETURN, 4)):
            subprocess.run([bench.KEY, str(g), str(k), "100"])
            time.sleep(wait)
        shot(g, os.path.join(out, f"{mode}-brightness.png"))
        if mode.startswith("port"):
            p.terminate()
        else:
            subprocess.run([os.path.join(bench.CX_BIN, "wineserver"), "-k"],
                           env=dict(os.environ, WINEPREFIX=bench.BOTTLE))
        try:
            p.wait(15)
        except subprocess.TimeoutExpired:
            p.kill()


if __name__ == "__main__":
    main()

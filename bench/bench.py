#!/usr/bin/env python3
"""One benchmark run of Dark Souls: the port or CrossOver, same save, same scene.

  bench.py <port|port-enhanced|crossover|crossover-dxvk> <out.json>

Launches the game visibly, presses Return through the title screens (held
100 ms, posted to the game's process like a key press), lets the save load,
then samples for 60 s while standing still: frame rate (the port's
FPS_REPORT / Wine's fps channel), CPU time of every process of the run, peak
memory and the GPU's utilisation. Then quits the game.
"""
import json, os, re, shutil, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY = os.path.join(ROOT, "bench/tools/key")
SAVE = os.path.expanduser("~/Library/Application Support/darksouls/drive_c/DRAKS0005.sl2")
BOTTLE = os.path.expanduser("~/Library/Application Support/CrossOver/Bottles/ds1bench")
CX_BIN = "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin"
WORK = os.environ.get("BENCH_WORK", "/tmp/ds1bench")

PRESS_AT = range(10, 73, 3)  # s after launch: Return, through every title screen
MEASURE_FROM, MEASURE_S = 100, 60


def game_env():
    env = dict(os.environ)
    for line in open(os.path.join(ROOT, "tools/local.env")):
        k, _, v = line.strip().partition("=")
        if k:
            env[k] = v.strip('"')
    return env


def launch(mode, log):
    if mode.startswith("port"):
        xdg = os.path.join(WORK, "xdg")
        shutil.rmtree(xdg, ignore_errors=True)
        os.makedirs(os.path.join(xdg, "darksouls/drive_c"))
        shutil.copy(SAVE, os.path.join(xdg, "darksouls/drive_c"))
        env = game_env()
        env.update(XDG_DATA_HOME=xdg, DARKSOULS_FPS_REPORT="1")
        for k in ("RECOMP_RT_BOOST", "RECOMP_UPSCALER", "DARKSOULS_ANISO", "MTL_HUD_ENABLED"):
            env.pop(k, None)
        if mode == "port-enhanced":
            env.update(RECOMP_RT_BOOST="1024x720:3,512x360:3,256x180:3,2048x2048:2",
                       RECOMP_UPSCALER="smaa", DARKSOULS_ANISO="16")
        exe = os.path.join(ROOT, "out/build/release/darksouls")
        p = subprocess.Popen([exe, "--game-dir", env["DARKSOULS_GAME_DIR"]], env=env,
                             stdout=log, stderr=subprocess.STDOUT)
        return p, lambda: [p.pid]
    shutil.copy(SAVE, os.path.join(BOTTLE, "drive_c/users/crossover/Documents/NBGI/DarkSouls/Player"))
    env = dict(os.environ, CX_DEBUG="+fps")  # wine --debugmsg; WINEDEBUG is overridden
    if mode == "crossover-dxvk":
        env["CX_GRAPHICS_BACKEND"] = "dxvk"
    p = subprocess.Popen([os.path.join(ROOT, "bench/cx_run.sh")], env=env,
                         stdout=log, stderr=subprocess.STDOUT)
    return p, crossover_pids


def crossover_pids():
    out = subprocess.run(["ps", "-ax", "-o", "pid=,command="], capture_output=True, text=True).stdout
    pids = []
    for line in out.splitlines():
        pid, _, cmd = line.strip().partition(" ")
        if "CrossOver.app" in cmd or re.match(r"(DATA|DARKSOULS)\.exe|cmd /c cd /d C:\\DarkSouls", cmd) \
                or re.search(r"C:\\windows\\system32\\\w+\.exe", cmd):
            pids.append(int(pid))
    return pids


def game_pid(mode, p):
    if mode.startswith("port"):
        return p.pid
    out = subprocess.run(["pgrep", "-f", "^DATA.exe"], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def front(pid):  # occluded windows are throttled: the game stays on top
    subprocess.run(["osascript", "-e", 'tell application "System Events" to set frontmost of '
                    f"(first process whose unix id is {pid}) to true"], capture_output=True)


def cpu_seconds(t):  # ps time: [[dd-]hh:]mm:ss.cc
    days, _, t = t.rpartition("-")
    parts = [float(x) for x in t.split(":")]
    s = 0.0
    for x in parts:
        s = s * 60 + x
    return s + (int(days) * 86400 if days else 0)


def sample(pids):
    if not pids:
        return 0.0, 0
    out = subprocess.run(["ps", "-o", "time=,rss=", "-p", ",".join(map(str, pids))],
                         capture_output=True, text=True).stdout
    cpu = rss = 0
    for line in out.splitlines():
        t, r = line.split()
        cpu += cpu_seconds(t)
        rss += int(r)
    return cpu, rss


def gpu_util():
    out = subprocess.run(["ioreg", "-r", "-d", "1", "-w", "0", "-c", "IOAccelerator"],
                         capture_output=True, text=True).stdout
    m = re.search(r'"Device Utilization %"=(\d+)', out)
    return int(m.group(1)) if m else None


def frame_rates(mode, logfile):
    text = open(logfile, errors="replace").read()
    if mode.startswith("port"):  # FPS_REPORT=1: "fps: 30.00 at t=..." once a second
        return [float(x) for x in re.findall(r"fps: (\d+\.\d+) at t=", text)]
    present = "win32u_vkQueuePresentKHR" if mode == "crossover-dxvk" else "wined3d_cs_exec_present"
    return [float(x) for x in re.findall(present + r" \S+ @ approx (\d+\.\d+)fps", text)]


def main():
    mode, out_json = sys.argv[1], sys.argv[2]
    os.makedirs(WORK, exist_ok=True)
    logfile = os.path.join(WORK, f"{mode}.log")
    idle_gpu = [gpu_util() for _ in range(5) if not time.sleep(1)]
    with open(logfile, "w") as log:
        t0 = time.time()
        p, pids = launch(mode, log)
        presses = list(PRESS_AT)
        while time.time() - t0 < MEASURE_FROM:
            if presses and time.time() - t0 >= presses[0]:
                presses.pop(0)
                g = game_pid(mode, p)
                if g:
                    front(g)
                    subprocess.run([KEY, str(g), "36", "100"])
            time.sleep(0.2)
        fps_lines_before = len(frame_rates(mode, logfile))
        cpu0, _ = sample(pids())
        t1 = time.time()
        gpu, rss_peak = [], 0
        while time.time() - t1 < MEASURE_S:
            time.sleep(1)
            gpu.append(gpu_util())
            rss_peak = max(rss_peak, sample(pids())[1])
            if time.time() - t1 > 5 and not os.path.exists(os.path.join(WORK, f"{mode}.png")):
                subprocess.run(["screencapture", "-x", os.path.join(WORK, f"{mode}.png")])
        cpu1, _ = sample(pids())
        wall = time.time() - t1
        if mode.startswith("port"):
            p.terminate()
        else:
            subprocess.run([os.path.join(CX_BIN, "wineserver"), "-k"],
                           env=dict(os.environ, WINEPREFIX=BOTTLE))
        try:
            p.wait(15)
        except subprocess.TimeoutExpired:
            p.kill()
    fps = frame_rates(mode, logfile)[fps_lines_before:]
    result = {
        "mode": mode,
        "fps": fps,
        "cpu_cores": (cpu1 - cpu0) / wall,
        "rss_peak_mb": rss_peak / 1024,
        "gpu_util": gpu,
        "gpu_idle": idle_gpu,
    }
    json.dump(result, open(out_json, "w"), indent=1)
    print(json.dumps({k: v for k, v in result.items() if k not in ("fps", "gpu_util", "gpu_idle")}),
          "fps", fps[:3], "...", "n", len(fps))


if __name__ == "__main__":
    main()

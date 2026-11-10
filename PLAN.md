# darksouls-mac: engineering notes

How the port is put together, what it took to get here, and what's left.
User-facing overview and build steps: [README.md](README.md).

## Target

Dark Souls: Prepare to Die Edition **1.0.2.0** (the last Games for Windows
LIVE build; `DATA.exe` SHA-256 `44d2dccb...6b52b6c`, checked by `lift.sh`).
32-bit, Direct3D 9, image base `0x400000`, no relocations (VAs are fixed),
no packer. `fmodex.dll` ships UPX-packed and is unpacked before lifting;
`fmod_event.dll` lifts as is.

## Layout

| Path | What |
|---|---|
| `src/main.cpp` | `recomp::GameConfig` for this game, the thread-priority hook |
| `manifest/*.manifest` | per-module lifter directives (`setjmp`, `resume`, `entry`, ...) |
| `symbols/` | Ghidra's function lists and jump tables, per module |
| `generated/` | lifter output (from your `DATA.exe`; not committed) |
| `vendor/x86recomp` | the recompiler and runtime (submodule, `darksouls` branch) |
| `tools/` | `build.sh` (locked build), `lift.sh`, `run.sh`, `app.sh`, analysis helpers |

FMOD is lifted as two extra modules (`GameConfig::lifted_dlls`,
`fmod_event` rebased to `0x11000000`) rather than reimplemented, so its 55
imports need no HLE.

## Game configuration (src/main.cpp)

- **Metal renderer** (`DARKSOULS_GFX=metal`): faster than SDL_GPU and reads
  depth textures the way D3D9 stores them.
- **Thread QoS**: the game starts its render thread at BELOW_NORMAL, which
  maps to macOS's utility class; its sleeps are coalesced, the frame limiter
  overshoots its 33 ms slot and frames snap to 66-80 ms. `thread_qos` holds
  every CRT-started thread at user-initiated: a steady 30 fps.
- **No placeholder gamepad** (`pad_slot_without_pad = false`): a listed pad
  switches the game's button prompts to a controller's.
- **DirectSound** linked (`recomp_dsound`): FMOD finds no WASAPI or WinMM
  output and falls back to it.

## What the port needed from x86recomp

All generic, on the library's `darksouls` branch:

- **Window on a worker thread.** The game creates and drives its window from
  a second thread; macOS allows window and view calls only on the main thread.
  Those calls run there (`RunOnUiThread`, `SDL_RunOnMainThread`), and the main
  thread pumps events while blocked in a guest wait.
- **Direct3D 9**: occlusion queries (reported visible), `GetRenderTargetData`,
  gamma ramps, `D3DXCreate(Cube)Texture`, COLOR2-3 varyings, depth-writing
  pixel shaders without a depth target, and depth-stencil format textures read
  as hardware shadow maps (`R_SHADOW`: compared with the coordinate's depth).
- **Process queries** for a start-up parent-process check (snapshot,
  `OpenProcess`, `GetProcessTimes`), `CreateFile` on directories, Unicode
  entry points, msvcr90 for the FMOD modules (including the `_CI` math
  helpers, which take their operands on the x87 stack), DirectSound loadable
  by name, xlive `XLiveOnDestroyDevice` and `XUserGetXUID`.
- **setjmp/longjmp** as non-local exits (`setjmp 00AE8794`, `resume 00AE31AE`
  in the manifest).
- **Input**: windows raised on show, DirectInput keys released on focus loss,
  `capture_cursor` (off here), input recording/replay and key logging.

Lessons worth keeping:

- A wrong stdcall argument count corrupts the guest stack and crashes far
  from the cause. Check every handler's count against the real signature.
- Two builds in one build directory corrupt `.ninja_deps`, which then forces
  full rebuilds of the lifted code. `tools/build.sh` takes a lock.
- When something seems slow, sample before optimising: the "slow frames" were
  idle threads waiting on coalesced sleeps, not CPU load.

## Open issues

1. **Fullscreen input**: keyboard input stops after switching to fullscreen.
2. **Clip planes with shaders** (`CLIPPLANEENABLE`): water reflections.
3. **Shadow filtering**: depth comparisons are single-tap (hard edges).
4. **Save location**: `C:\DRAKS0005.sl2` at the root of the virtual drive;
   the game gets no proper Documents path.
5. **60 fps** (optional): the game is balanced for 30; an opt-in unlock
   would need the limiter's target and the frame-rate-dependent physics
   handled, as DSFix does.

## How keyboard input reaches the menus

Fixed; kept because the path is long. Each of the four player slots is a
composite device (vtable `0x011103BC`) over a pad, a mouse and a keyboard
(`0x01110D1C`); its `IsKeyDown` ORs the children's. Every frame the input
listeners map keys to virtual buttons (`0x00-0x35`) through the binding
tables on top of their context stacks (`f_00698170`, `f_00695360`). The
contexts are rebuilt (`f_00F9D750`) from a 38-entry key configuration
whenever it changes (`f_00F9F240`), and that configuration is read with
`GetPrivateProfileIntW`, one key at a time, with the built-in binding as
the default. The HLE returned the file name pointer instead of the
default, so every key became `0x0038DF04` and the menu contexts kept only
pad buttons.

## Debugging

- `DARKSOULS_TRACE=1`: every HLE call with arguments and results.
- Fault reports name the guest address and registers; an "indirect branch to
  unlifted address" means a manifest entry is missing.
- Temporary probes in `generated/*.cpp` (an `fprintf` at an instruction)
  recompile in seconds; restore the file afterwards.
- `sample <pid> 10` while playing shows where host time goes per thread.
- Hidden test runs: `DARKSOULS_HIDDEN=1 DARKSOULS_BACKGROUND=1
  DARKSOULS_TEST_FOCUS=1,2 DARKSOULS_TEST_INPUT=script DARKSOULS_SHOT_DIR=dir`.

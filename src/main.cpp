// darksouls: Dark Souls: Prepare to Die Edition (PC, 1.0.2.0), natively.
//
//   darksouls [--game-dir DIR] [-- GAME ARGS...]
//
// DIR is the game install: the folder holding DATA/ (DATA.exe, dvdbnd0-3,
// movWW). Defaults to $DARKSOULS_GAME_DIR. Arguments after `--` go on the
// game's own command line. Set DARKSOULS_TRACE=1 to log every HLE call.

#include <sys/stat.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "runtime/log.h"
#include "runtime/platform.h"
#include "runtime/runtime.h"

namespace {

// The game's threads start through its CRT's thread wrapper; it gives some
// (the render thread among them) BELOW_NORMAL priority, which maps to the
// utility class on macOS, where sleeps are coalesced and run late: the
// frame limiter's Sleep then overshoots its 33 ms slot and frames snap to
// the next one (66-80 ms). None of them goes below user-initiated; FMOD's
// threads and the main thread keep the class their priority gives.
constexpr recomp::gaddr kCrtThreadStart = 0x00AE857A;

bool DarkSoulsThreadQos(recomp::gaddr entry, uint64_t, recomp::platform::ThreadQos* out) {
  if (entry != kCrtThreadStart) return false;
  out->cls = recomp::platform::ThreadQos::kUserInitiated;
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  std::string game_dir, game_args;
  if (const char* e = std::getenv("DARKSOULS_GAME_DIR")) game_dir = e;
  for (int i = 1; i < argc; i++) {
    if (!std::strcmp(argv[i], "--game-dir") && i + 1 < argc) {
      game_dir = argv[++i];
    } else if (!std::strcmp(argv[i], "--")) {
      for (i++; i < argc; i++) {
        if (!game_args.empty()) game_args += ' ';
        bool quote = std::strpbrk(argv[i], " \t") != nullptr;
        if (quote) game_args += '"';
        game_args += argv[i];
        if (quote) game_args += '"';
      }
    } else {
      std::fprintf(stderr, "usage: %s [--game-dir DIR] [-- GAME ARGS...]\n", argv[0]);
      return 2;
    }
  }
  if (game_dir.empty()) {
    std::fprintf(stderr, "darksouls: pass --game-dir or set DARKSOULS_GAME_DIR\n");
    return 2;
  }
  while (game_dir.size() > 1 && game_dir.back() == '/') game_dir.pop_back();
  if (const char* t = std::getenv("DARKSOULS_TRACE")) recomp::g_trace = *t && *t != '0';

  const std::string exe = game_dir + "/DATA/DATA.exe";
  struct stat st;
  if (stat(exe.c_str(), &st) != 0) {
    std::fprintf(stderr, "darksouls: %s not found\n", exe.c_str());
    return 2;
  }

  recomp::GameConfig game;
  game.id = "darksouls";
  // The retail install path; DATA.exe lives in DATA/ and is started there.
  game.guest_dir = "C:\\Program Files (x86)\\Bandai Namco Games\\Dark Souls Prepare To Die Edition";
  game.exe_name = "DATA\\DATA.exe";
  game.current_dir = game.guest_dir + "\\DATA";
  // PTDE refuses to start below ~1.5 GiB; it sizes caches from this.
  game.total_phys_mb = 4096;
  game.video_memory_mb = 1024;
#if defined(__APPLE__)
  // The Metal renderer (depth textures read as D3D9 stores them, faster than
  // SDL_GPU); DARKSOULS_GFX=gpu still picks the other.
  setenv("DARKSOULS_GFX", "metal", 0);
#endif
  // A listed gamepad switches the game's button prompts to a pad's; with
  // none connected, keyboard and mouse prompts.
  game.pad_slot_without_pad = false;
  game.thread_qos = DarkSoulsThreadQos;
  // The game's own anti-aliasing pass (on by default with no .ini) renders
  // the scene black here; RECOMP_UPSCALER=smaa anti-aliases the frame.
  game.profile_ints = {{"DisplaySettingFilter", "ForceDisableAA", 1}};
#if defined(__APPLE__)
  // Full screen as a Space of its own, which is what Game Mode needs.
  game.mac_fullscreen_space = true;
#endif
  // FMOD: lifted as modules (GameConfig::lifted_dlls) so their 55 imports
  // don't need HLE reimplementations. The path is relative to guest_dir, and
  // a retail install keeps both DLLs in DATA/ next to the exe; the loader
  // matches them by file name, so the game's own LoadLibrary("fmodex.dll")
  // finds the mapped image instead of reading from disk.
  game.lifted_dlls = {{"DATA\\fmodex.dll"}, {"DATA\\fmod_event.dll", 0x11000000}};
  return recomp::RunProcess(game, exe, game_dir, game_args);
}

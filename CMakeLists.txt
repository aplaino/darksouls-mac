cmake_minimum_required(VERSION 3.25)
project(darksouls LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
# x86recomp's runtime and HLE modules are shared libraries: rebuilding one
# does not relink the game.
set(CMAKE_LINK_DEPENDS_NO_SHARED ON)

# x86recomp: the lifter, x87 model and runtime (vendor/x86recomp, the
# commit pinned in X86RECOMP, on Awis13/x86recomp's `liberty` branch).
set(X86RECOMP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/x86recomp"
    CACHE PATH "x86recomp source tree")

enable_testing()
set(RECOMP_LTO ON CACHE BOOL "ThinLTO of lifted code")
set(RECOMP_SSE_HOST ON CACHE BOOL "Host SSE arithmetic in lifted code")
add_subdirectory("${X86RECOMP_DIR}" x86recomp)

# The game: runtime + HLE + lifted code (generated/, produced by
# recomp_lift from the user's own install; see tools/lift.sh).
recomp_add_lifted(darksouls_lifted "${CMAKE_CURRENT_SOURCE_DIR}/generated")
if(TARGET darksouls_lifted)
  add_executable(darksouls src/main.cpp $<TARGET_OBJECTS:darksouls_lifted>)
  if(RECOMP_LTO)
    target_link_options(darksouls PRIVATE -flto=thin
      "LINKER:-cache_path_lto,${CMAKE_BINARY_DIR}/lto-cache")
  endif()
  target_include_directories(darksouls PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/generated")
  # recomp_dsound: FMOD finds no WASAPI or WinMM output here and falls back
  # to DirectSound, which it loads with LoadLibrary("dsound.dll").
  target_link_libraries(darksouls PRIVATE recomp_runtime recomp_d3d9
                        recomp_dinput8 recomp_xinput recomp_xlive recomp_dsound)
  set_target_properties(darksouls PROPERTIES ENABLE_EXPORTS ON)  # names in fault backtraces
endif()

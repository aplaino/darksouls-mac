# What the Builder carries, and its licenses

Nothing of Dark Souls: its code is translated and compiled on your Mac from
your own copy of the game.

| Part | License | Source |
|---|---|---|
| darksouls-mac (main.cpp, manifests, symbols, the Builder) | MIT | https://github.com/aplaino/darksouls-mac |
| x86recomp (the lifter, the runtime libraries and headers) | MIT | https://github.com/aplaino/x86recomp (branch `darksouls`) |
| SDL 3.4.20 | zlib | https://github.com/libsdl-org/SDL |
| FFmpeg 9.0.2 (libavcodec, libavformat, libavutil, libswscale; MP3 and Bink only), linked dynamically | LGPL 2.1 or later | https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz |
| glslang 16.6.0 | BSD-3-Clause and others | https://github.com/KhronosGroup/glslang |
| SPIRV-Cross vulkan-sdk-1.4.363.0 | Apache 2.0 | https://github.com/KhronosGroup/SPIRV-Cross |
| UPX 5.3.0 | GPL 2.0 or later, with the UPX exception | https://github.com/upx/upx |

`tools/deps.sh` in the repository builds each of them from the source above.

#!/bin/zsh
# deps.sh: the libraries the runtime links, built from source for macOS
# into out/deps/prefix, so the Builder carries nothing from Homebrew:
#   SDL3 (a dylib: every runtime library shares one), FFmpeg (dylibs, LGPL,
#   only what the runtime uses: MP3 and Bink), glslang and SPIRV-Cross
#   (static, inside librecomp_gfx), and UPX (the lifter needs fmodex.dll
#   unpacked).
# The versions are Homebrew's at the time, so a Homebrew build and a Builder
# build compile the same code. Needs cmake and ninja to run.
set -euo pipefail
here=${0:A:h:h}
w=$here/out/deps
prefix=$w/prefix
src=$w/src
mkdir -p $prefix $src
export MACOSX_DEPLOYMENT_TARGET=14.0
jobs=$(sysctl -n hw.ncpu)

fetch() {  # url sha256 -> unpacked directory in $src
  local url=$1 sum=$2 file=$src/${1:t}
  [[ -f $file ]] || curl -fL --retry 3 -o $file $url
  [[ $(shasum -a 256 $file | cut -d' ' -f1) == $sum ]] || { echo "deps.sh: checksum of ${file:t}" >&2; exit 1; }
  local dir=$src/${${file:t}%.tar.*}
  [[ -d $dir ]] || { mkdir -p $dir && tar -xf $file -C $dir --strip-components 1; }
  echo $dir
}

# What ships names no folder of this Mac: source paths (assertions) as
# deps/..., and FFmpeg's configure line without the prefix.
map=-ffile-prefix-map=$w=deps

cmake_dep() {  # source dir, then cmake options
  local s=$1; shift
  cmake -S $s -B $s/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$prefix \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew \
    -DCMAKE_C_FLAGS=$map -DCMAKE_CXX_FLAGS=$map "$@" > /dev/null
  cmake --build $s/build -j $jobs > /dev/null
  cmake --install $s/build > /dev/null
}

if [[ ! -f $prefix/lib/libSDL3.0.dylib ]]; then
  echo "deps.sh: SDL3"
  s=$(fetch https://github.com/libsdl-org/SDL/releases/download/release-3.4.20/SDL3-3.4.20.tar.gz \
        f3bb06f55bed9557227a700af2ea62e49497ebdf58037732a731a5fb3ef8581f)
  cmake_dep $s -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
fi

if [[ ! -f $prefix/lib/libavcodec.dylib ]]; then
  echo "deps.sh: FFmpeg"
  s=$(fetch https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz \
        8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e)
  (cd $s && ./configure --prefix=$prefix --arch=arm64 --cc=clang --enable-shared --disable-static \
     --install-name-dir=@rpath --disable-autodetect --disable-programs --disable-doc \
     --disable-avdevice --disable-avfilter --disable-swresample --disable-everything \
     --enable-decoder=mp3,mp3float,bink,binkaudio_rdft,binkaudio_dct --enable-demuxer=bink,mp3 \
     --enable-parser=mpegaudio --enable-protocol=file --enable-swscale --extra-cflags=$map > /dev/null &&
   sed -i '' -e "s|$w|deps|g" config.h &&
   make -j $jobs > /dev/null && make install > /dev/null)
fi

if [[ ! -f $prefix/lib/libglslang.a ]]; then
  echo "deps.sh: glslang"
  s=$(fetch https://github.com/KhronosGroup/glslang/archive/refs/tags/16.6.0.tar.gz \
        9c09b901149c729df745057dafa815278aaa101b84d2b6e14f16a42de52f97f2)
  cmake_dep $s -DBUILD_SHARED_LIBS=OFF -DENABLE_OPT=OFF -DGLSLANG_TESTS=OFF -DENABLE_GLSLANG_BINARIES=ON
fi

if [[ ! -f $prefix/lib/libspirv-cross-msl.a ]]; then
  echo "deps.sh: SPIRV-Cross"
  s=$(fetch https://github.com/KhronosGroup/SPIRV-Cross/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz \
        f708982e88b763ef5b0394ed468fc2c3628f68cdab89f2e7a946cd628c04e721)
  cmake_dep $s -DSPIRV_CROSS_SHARED=OFF -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_CLI=ON \
    -DSPIRV_CROSS_ENABLE_TESTS=OFF
fi

if [[ ! -x $prefix/bin/upx ]]; then
  echo "deps.sh: UPX"
  s=$(fetch https://github.com/upx/upx/releases/download/v5.3.0/upx-5.3.0-src.tar.xz \
        6229b5564dd91dd423a5280a7c15b70fc05449d2605bb853ce076743057fcf55)
  cmake_dep $s -DUPX_CONFIG_DISABLE_WERROR=ON -DUPX_CONFIG_DISABLE_SELF_PACK_TEST=ON
fi

echo "deps.sh: $prefix"

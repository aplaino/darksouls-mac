#!/bin/zsh
# make_builder.sh: makes out/builder/Dark Souls Builder.zip, the app that
# builds the game on a Mac with nothing but Apple's Command Line Tools.
#   builder/make_builder.sh          (needs what tools/setup.sh installs)
# This Mac's lift (generated/, tools/lift.sh) is only used to configure the
# reference build the recipe is read from; nothing of the game goes into the
# Builder, which checks that before zipping it.
#   1. the libraries from source (tools/deps.sh): nothing from Homebrew ships
#   2. the reference build (out/kit): the lifter and the runtime libraries
#   3. the kit: lifter, UPX, symbols, manifests, main.cpp, headers, the app
#      without its executable, and the recipe (builder/make_recipe.py)
#   4. the Builder (SwiftUI, no Xcode needed) with the kit in its
#      Resources, signed ad hoc and zipped
set -euo pipefail
here=${0:A:h:h}
cd $here
[[ -n $(ls generated/gen_*.cpp 2>/dev/null) ]] || { echo "make_builder: lift first (tools/lift.sh)"; exit 1; }
deps=$here/out/deps/prefix
kb=$here/out/kit
out=$here/out/builder
say() { print -P "\n%B==> $*%b" }

say "Libraries from source"
tools/deps.sh

say "Reference build"
llvm=/opt/homebrew/opt/llvm@22
# Paths in the kit's binaries (assertions, debug info) without this Mac's.
map="-ffile-prefix-map=$here/vendor/x86recomp=x86recomp -ffile-prefix-map=$here=darksouls-mac"
PKG_CONFIG_LIBDIR=$deps/lib/pkgconfig cmake -S . -B $kb -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_FLAGS=$map -DCMAKE_CXX_FLAGS=$map -DCMAKE_OBJCXX_FLAGS=$map \
  -DCMAKE_PREFIX_PATH=$deps -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew \
  -DRECOMP_GLSLANG=$deps/bin/glslang -DRECOMP_SPIRV_CROSS=$deps/bin/spirv-cross \
  -DRECOMP_LLVM_ROOT=$llvm -DRECOMP_LLVM_DEMANGLE=$llvm/lib/libLLVMDemangle.a \
  -DRECOMP_LTO=ON -DRECOMP_SSE_HOST=ON -DRECOMP_HOST_CPU=apple-m1 > /dev/null
cmake --build $kb --target recomp_lift recomp_runtime recomp_d3d9 recomp_dinput8 recomp_xinput \
  recomp_xlive recomp_dsound

say "Kit"
kit=$out/kit
rm -rf $out && mkdir -p $kit/bin $kit/manifest $kit/src $kit/include
tools/app.sh --kit $kb $deps $kit/app/DarkSouls.app
cp $kb/x86recomp/tools/lifter/recomp_lift $deps/bin/upx $kit/bin/
for dep in $(otool -L $kit/bin/recomp_lift | awk '$1 ~ /^@rpath\// {sub("@rpath/", "", $1); print $1}'); do
  cp $kb/x86recomp/$dep $kit/bin/
done
for f in $kit/bin/*(.); do
  otool -l $f | awk '/cmd LC_RPATH/ {r = 1} r && $1 == "path" {print $2; r = 0}' | while read -r rp; do
    install_name_tool -delete_rpath $rp $f
  done
done
install_name_tool -add_rpath @executable_path $kit/bin/recomp_lift
cp -R symbols $kit/symbols
cp manifest/*.manifest $kit/manifest/
cp src/main.cpp $kit/src/
# The runtime's headers (and lifted_table.cpp, compiled with the game).
rsync -a --include='*/' --include='*.h' --include='*.inc' --include='lifted_table.cpp' --exclude='*' \
  vendor/x86recomp/src/ $kit/include/runtime/
cp -R $deps/include $kit/include/deps
python3 builder/make_recipe.py $kb $here $deps $kit
cp builder/LICENSES.md $kit/

# Nothing that names this Mac, and nothing of the game.
if grep -rlI -e "$HOME" -e /opt/homebrew $kit/recipe.json $kit/src $kit/app/*/Contents/MacOS; then
  echo "make_builder: a path of this Mac in the kit"; exit 1
fi
for f in $kit/bin/*(.) $kit/app/*/Contents/Frameworks/*.dylib; do
  if otool -L $f | tail -n +2 | grep -q -e /opt/homebrew -e "$HOME"; then
    echo "make_builder: $f links outside the kit:"; otool -L $f; exit 1
  fi
done
if [[ -n $(find $kit -iname '*.exe' -o -iname '*.dll' -o -name 'gen_*') ]]; then
  echo "make_builder: game files in the kit"; exit 1
fi

say "Builder"
b="$out/Dark Souls Builder.app"
mkdir -p "$b/Contents/MacOS" "$b/Contents/Resources"
xcrun swiftc -O -parse-as-library -target arm64-apple-macos14.0 -swift-version 5 \
  builder/Sources/*.swift -o "$b/Contents/MacOS/Builder"
cp builder/Info.plist "$b/Contents/"
mv $kit "$b/Contents/Resources/kit"
find "$b/Contents/Resources/kit" -type f -print0 | while IFS= read -r -d '' f; do
  file -b "$f" | grep -q '^Mach-O' && codesign --force --sign - "$f"
done
codesign --force --sign - "$b"
codesign --verify --strict "$b"
(cd $out && ditto -c -k --keepParent "Dark Souls Builder.app" "Dark Souls Builder.zip")
echo "make_builder: $out/Dark Souls Builder.zip ($(du -sh "$out/Dark Souls Builder.zip" | cut -f1))"

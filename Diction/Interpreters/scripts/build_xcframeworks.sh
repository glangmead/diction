#!/bin/bash
# Build XCFrameworks for Bocfel and Glulxe, each statically linked with RemGlk
# and our bridge code. Hidden visibility so the two frameworks can coexist
# even though they have overlapping internal symbol names (glk_main, etc.).
#
# Output: Diction/Interpreters/build/{Bocfel,Glulxe}.xcframework

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
SOURCES="$ROOT/sources"
BRIDGE="$ROOT/bridge"
BUILD="$ROOT/build"
DEPLOY_TARGET="18.0"

rm -rf "$BUILD"
mkdir -p "$BUILD"

REMGLK_C=(
  rgevent.c rgfref.c rggestal.c rgdata.c rgmisc.c rgauto.c
  rgstream.c rgstyle.c rgwin_blank.c rgwin_buf.c rgwin_grid.c
  rgwin_pair.c rgwin_graph.c rgwindow.c rgschan.c rgblorb.c
  cgunicod.c cgdate.c gi_dispa.c gi_debug.c gi_blorb.c
)

GLULXE_C=(
  main.c files.c vm.c exec.c funcs.c operand.c string.c glkop.c
  heap.c serial.c search.c accel.c float.c gestalt.c osdepend.c
  profile.c debugger.c unixstrt.c unixautosave.c
)

BOCFEL_CPP=(
  blorb.cpp branch.cpp dict.cpp iff.cpp io.cpp mathop.cpp meta.cpp
  memory.cpp objects.cpp options.cpp osdep.cpp patches.cpp
  process.cpp random.cpp screen.cpp sound.cpp stack.cpp stash.cpp
  unicode.cpp util.cpp zoom.cpp zterp.cpp glkstart.cpp
)

COMMON_CFLAGS="-Os -fvisibility=hidden -Wno-implicit-function-declaration -Wno-unused-result -Wno-deprecated-declarations"
REMGLK_INCLUDE="-I$SOURCES/remglk"
EXIT_RENAME="-Dglk_exit=bridge_glk_exit"
GLULXE_DEFINES="-DOS_UNIX -DUNIX_RAND_ARC4 $EXIT_RENAME"
BOCFEL_DEFINES="-DZTERP_GLK -DZTERP_GLK_UNIX -DZTERP_GLK_BLORB -DZTERP_OS_UNIX $EXIT_RENAME"

build_remglk_objects() {
  local arch="$1" sdk="$2" outdir="$3" extra_defines="$4" cc
  cc=$(xcrun --sdk "$sdk" --find clang)
  local sdkroot
  sdkroot=$(xcrun --sdk "$sdk" --show-sdk-path)
  local target
  if [ "$sdk" = "iphoneos" ]; then
    target="${arch}-apple-ios${DEPLOY_TARGET}"
  else
    target="${arch}-apple-ios${DEPLOY_TARGET}-simulator"
  fi
  mkdir -p "$outdir/remglk"
  for f in "${REMGLK_C[@]}"; do
    "$cc" -isysroot "$sdkroot" -target "$target" $COMMON_CFLAGS \
      $REMGLK_INCLUDE -c "$SOURCES/remglk/$f" -o "$outdir/remglk/${f%.c}.o"
  done
  "$cc" -isysroot "$sdkroot" -target "$target" $COMMON_CFLAGS \
    $REMGLK_INCLUDE $extra_defines -c "$BRIDGE/remglk_main_bridge.c" \
    -o "$outdir/remglk/remglk_main_bridge.o"
}

build_glulxe_lib() {
  local arch="$1" sdk="$2" outdir="$3"
  local cc
  cc=$(xcrun --sdk "$sdk" --find clang)
  local sdkroot
  sdkroot=$(xcrun --sdk "$sdk" --show-sdk-path)
  local target
  if [ "$sdk" = "iphoneos" ]; then
    target="${arch}-apple-ios${DEPLOY_TARGET}"
  else
    target="${arch}-apple-ios${DEPLOY_TARGET}-simulator"
  fi
  build_remglk_objects "$arch" "$sdk" "$outdir" "$GLULXE_DEFINES"
  mkdir -p "$outdir/glulxe"
  for f in "${GLULXE_C[@]}"; do
    "$cc" -isysroot "$sdkroot" -target "$target" $COMMON_CFLAGS \
      $GLULXE_DEFINES $REMGLK_INCLUDE -I"$SOURCES/glulxe" \
      -c "$SOURCES/glulxe/$f" -o "$outdir/glulxe/${f%.c}.o"
  done
  "$cc" -isysroot "$sdkroot" -target "$target" $COMMON_CFLAGS \
    $REMGLK_INCLUDE -I"$BRIDGE" $GLULXE_DEFINES \
    -c "$BRIDGE/glulxe_bridge.c" -o "$outdir/glulxe/glulxe_bridge.o"
  # Mega-object link: demotes private external symbols (hidden visibility)
  # to local, so two interpreter frameworks can coexist without clashes.
  local ldver="${DEPLOY_TARGET} ${DEPLOY_TARGET}"
  local platform_args
  if [ "$sdk" = "iphoneos" ]; then
    platform_args="-platform_version ios $ldver"
  else
    platform_args="-platform_version ios-simulator $ldver"
  fi
  ld -r -arch "$arch" $platform_args -syslibroot "$sdkroot" \
    -o "$outdir/Glulxe-merged.o" \
    "$outdir/remglk"/*.o "$outdir/glulxe"/*.o
  /usr/bin/libtool -static -o "$outdir/libGlulxe.a" "$outdir/Glulxe-merged.o"
}

build_bocfel_lib() {
  local arch="$1" sdk="$2" outdir="$3"
  local cc cxx
  cc=$(xcrun --sdk "$sdk" --find clang)
  cxx=$(xcrun --sdk "$sdk" --find clang++)
  local sdkroot
  sdkroot=$(xcrun --sdk "$sdk" --show-sdk-path)
  local target
  if [ "$sdk" = "iphoneos" ]; then
    target="${arch}-apple-ios${DEPLOY_TARGET}"
  else
    target="${arch}-apple-ios${DEPLOY_TARGET}-simulator"
  fi
  build_remglk_objects "$arch" "$sdk" "$outdir" "$BOCFEL_DEFINES"
  mkdir -p "$outdir/bocfel"
  for f in "${BOCFEL_CPP[@]}"; do
    "$cxx" -isysroot "$sdkroot" -target "$target" -std=c++17 \
      $COMMON_CFLAGS $BOCFEL_DEFINES $REMGLK_INCLUDE \
      -I"$SOURCES/bocfel" \
      -c "$SOURCES/bocfel/$f" -o "$outdir/bocfel/${f%.cpp}.o"
  done
  "$cxx" -isysroot "$sdkroot" -target "$target" -std=c++17 \
    $COMMON_CFLAGS $REMGLK_INCLUDE -I"$BRIDGE" $BOCFEL_DEFINES \
    -c "$BRIDGE/bocfel_bridge.cpp" -o "$outdir/bocfel/bocfel_bridge.o"
  local ldver="${DEPLOY_TARGET} ${DEPLOY_TARGET}"
  local platform_args
  if [ "$sdk" = "iphoneos" ]; then
    platform_args="-platform_version ios $ldver"
  else
    platform_args="-platform_version ios-simulator $ldver"
  fi
  ld -r -arch "$arch" $platform_args -syslibroot "$sdkroot" \
    -o "$outdir/Bocfel-merged.o" \
    "$outdir/remglk"/*.o "$outdir/bocfel"/*.o
  /usr/bin/libtool -static -o "$outdir/libBocfel.a" "$outdir/Bocfel-merged.o"
}

make_xcframework() {
  local name="$1" lib="$2"
  local device_dir="$BUILD/$name-iphoneos"
  local sim_dir="$BUILD/$name-iphonesimulator"
  rm -rf "$BUILD/$name.xcframework"

  # No headers inside the XCFramework — the bridging header reaches
  # interp_bridge.h via HEADER_SEARCH_PATHS in the consuming target.
  xcodebuild -create-xcframework \
    -library "$device_dir/$lib" \
    -library "$sim_dir/$lib" \
    -output "$BUILD/$name.xcframework"
}

echo "Building Glulxe (iphoneos arm64)"
build_glulxe_lib arm64 iphoneos "$BUILD/Glulxe-iphoneos"
echo "Building Glulxe (iphonesimulator arm64)"
build_glulxe_lib arm64 iphonesimulator "$BUILD/Glulxe-iphonesimulator"
echo "Packaging Glulxe.xcframework"
make_xcframework Glulxe libGlulxe.a

echo "Building Bocfel (iphoneos arm64)"
build_bocfel_lib arm64 iphoneos "$BUILD/Bocfel-iphoneos"
echo "Building Bocfel (iphonesimulator arm64)"
build_bocfel_lib arm64 iphonesimulator "$BUILD/Bocfel-iphonesimulator"
echo "Packaging Bocfel.xcframework"
make_xcframework Bocfel libBocfel.a

echo "Done. XCFrameworks in $BUILD"

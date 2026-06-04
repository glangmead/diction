#!/bin/bash
# Fetch the classic Glk + Quixe + ZVM stack — the autosave-capable web IF stack
# that Lectrote uses — and copy the built JS into the app's Resources.
#
# Sourcing:
#  - Quixe (built lib/quixe.min.js) AND the internally-consistent classic Glk
#    stack it vendors (glkapi/dialog/gi_blorb in src/glkote, gi_dispa/gi_load in
#    src/quixe) come from erkyrath/quixe at a pinned commit. Taking the whole
#    Glk+Quixe half from one commit avoids cross-repo version skew. The bridge
#    supplies its own headless GlkOte, so the jQuery-bound glkote.js display
#    layer is deliberately NOT vendored.
#  - ZVM (the Z-machine VM) comes from the curiousdannii/ifvms npm package,
#    pinned exactly in package.json, because its built dist/zvm.js is not
#    committed to the repo. Run `npm install` before this script.
#
# Bump the pin below (and the ifvms version in package.json) and re-run to
# update. Sources land in sources/ (gitignored, like fetch_sources.sh); built JS
# lands in the app's Interpreter/Resources.
set -euo pipefail

cd "$(dirname "$0")/.."
INTERP_ROOT="$(pwd)"                                    # .../Diction/Interpreters
SOURCES="$INTERP_ROOT/sources"
RES="$INTERP_ROOT/../Diction/Interpreter/Resources"     # app Interpreter/Resources
LICENSES="$INTERP_ROOT/../Diction/Resources/Licenses"   # app Resources/Licenses
NODE_MODULES="$INTERP_ROOT/../../node_modules"           # repo-root node_modules

QUIXE_REPO="https://github.com/erkyrath/quixe.git"
QUIXE_COMMIT="d1710c27b0ac293d40bc67cb1b3de38c1ef7fa9f"

mkdir -p "$SOURCES" "$RES" "$LICENSES"

echo "Fetching quixe at $QUIXE_COMMIT"
rm -rf "$SOURCES/quixe"
git clone --quiet "$QUIXE_REPO" "$SOURCES/quixe"
( cd "$SOURCES/quixe" && git checkout --quiet "$QUIXE_COMMIT" )
rm -rf "$SOURCES/quixe/.git"

echo "Copying Quixe VM + classic Glk stack into Resources"
cp "$SOURCES/quixe/lib/quixe.min.js"       "$RES/quixe.min.js"
cp "$SOURCES/quixe/src/glkote/glkapi.js"   "$RES/glkapi.js"
cp "$SOURCES/quixe/src/glkote/dialog.js"   "$RES/dialog.js"
cp "$SOURCES/quixe/src/glkote/gi_blorb.js" "$RES/gi_blorb.js"
cp "$SOURCES/quixe/src/quixe/gi_dispa.js"  "$RES/gi_dispa.js"
cp "$SOURCES/quixe/src/quixe/gi_load.js"   "$RES/gi_load.js"
cp "$SOURCES/quixe/LICENSE"                "$LICENSES/quixe.txt"

echo "Copying ZVM (ifvms) into Resources"
if [ ! -f "$NODE_MODULES/ifvms/dist/zvm.js" ]; then
  echo "error: node_modules/ifvms/dist/zvm.js missing — run 'npm install' first" >&2
  exit 1
fi
cp "$NODE_MODULES/ifvms/dist/zvm.js" "$RES/zvm.js"
# ZVM's own Glk dispatch layer (GiDispa). ZVM calls glkapi directly, so it needs
# this — NOT quixe's gi_dispa (which is for Glulx). The source file is
# self-contained (module.exports + window.GiDispa), so vendor it as-is.
cp "$NODE_MODULES/ifvms/src/zvm/dispatch.js" "$RES/zvm_dispatch.js"
cp "$NODE_MODULES/ifvms/LICENSE"     "$LICENSES/ifvms.txt"

echo "Glk stack vendored into $RES:"
echo "  quixe.min.js glkapi.js dialog.js gi_blorb.js gi_dispa.js gi_load.js zvm.js"

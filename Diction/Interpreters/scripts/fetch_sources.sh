#!/bin/bash
# Fetch the three vendored interpreter sources at pinned commits.
# Removes each repo's .git directory after checkout so the working tree
# stays clean (the sources/ directory is gitignored from the parent project).
#
# Update the commit SHAs below to bump versions. Verify the new sources
# still build with build_xcframeworks.sh.

set -euo pipefail

cd "$(dirname "$0")/.."
SOURCES="$(pwd)/sources"

REMGLK_REPO="https://github.com/erkyrath/remglk.git"
REMGLK_COMMIT="7d53a46a9d40d2e569b154e4740e8ac4eee67cb8"

GLULXE_REPO="https://github.com/erkyrath/glulxe.git"
GLULXE_COMMIT="56ab8743bab565de307bd892c555d8d8897ed517"

BOCFEL_REPO="https://github.com/erkyrath/bocfel.git"
BOCFEL_COMMIT="f3bab004d2c16be3f8000b82e4da9cb5f74d30dd"

fetch_at_commit() {
  local repo="$1" commit="$2" dest="$3"
  echo "Fetching $(basename "$dest") at $commit"
  rm -rf "$dest"
  git clone --quiet "$repo" "$dest"
  (cd "$dest" && git checkout --quiet "$commit")
  rm -rf "$dest/.git"
}

mkdir -p "$SOURCES"
fetch_at_commit "$REMGLK_REPO" "$REMGLK_COMMIT" "$SOURCES/remglk"
fetch_at_commit "$GLULXE_REPO" "$GLULXE_COMMIT" "$SOURCES/glulxe"
fetch_at_commit "$BOCFEL_REPO" "$BOCFEL_COMMIT" "$SOURCES/bocfel"

echo "Sources fetched into $SOURCES"
echo "Run scripts/build_xcframeworks.sh to build the XCFrameworks."

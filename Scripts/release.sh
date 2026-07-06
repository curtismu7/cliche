#!/bin/bash
# Tags, pushes, and publishes a GitHub release with the dist zip.
# Bump the VERSION file first; the working tree must be clean.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
TAG="v$VERSION"

if [ -n "$(git status --porcelain)" ]; then
    echo "❌ Working tree not clean — commit first."
    exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "❌ Tag $TAG already exists — bump the VERSION file."
    exit 1
fi

echo "── Releasing Cliché $VERSION ──"
echo "Running tests…"
swift run cliche-selftest >/dev/null

Scripts/make-dist.sh

git tag "$TAG"
git push origin main "$TAG"
gh release create "$TAG" "build/Cliche-$VERSION.zip" "build/Cliche-$VERSION.dmg" \
    --title "Cliché $VERSION" \
    --generate-notes
echo "✅ Released: https://github.com/curtismu7/cliche/releases/tag/$TAG"

# Keep the Homebrew tap current: bump version + sha256, commit, push.
TAP_DIR="$HOME/Development/homebrew-cliche"
TAP_REPO="https://github.com/curtismu7/homebrew-cliche.git"
CASK="$TAP_DIR/Casks/cliche.rb"
if [ ! -d "$TAP_DIR/.git" ]; then
    echo "Cloning Homebrew tap…"
    git clone "$TAP_REPO" "$TAP_DIR"
fi
if [ -f "$CASK" ]; then
    SHA256="$(shasum -a 256 "build/Cliche-$VERSION.zip" | cut -d' ' -f1)"
    sed -i '' \
        -e "s/^  version \".*\"/  version \"$VERSION\"/" \
        -e "s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" \
        "$CASK"
    git -C "$TAP_DIR" add Casks/cliche.rb
    git -C "$TAP_DIR" commit -m "Update cliche cask to $VERSION"
    git -C "$TAP_DIR" push
    echo "🍺 Homebrew tap updated to $VERSION"
else
    echo "⚠️  Homebrew cask not found at $CASK — tap NOT updated."
fi

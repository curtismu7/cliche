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
gh release create "$TAG" "build/Cliche-$VERSION.zip" \
    --title "Cliché $VERSION" \
    --generate-notes
echo "✅ Released: https://github.com/curtismu7/cliche/releases/tag/$TAG"

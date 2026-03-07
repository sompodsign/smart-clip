#!/bin/bash
set -euo pipefail

# ─── SmartClip Release Script ───
# Usage: ./release.sh          → auto-bumps patch (0.1.0 → 0.2.0)
#        ./release.sh minor    → bumps minor (0.1.0 → 0.2.0)
#        ./release.sh major    → bumps major (0.1.0 → 1.0.0)
#        ./release.sh patch    → bumps patch (0.1.0 → 0.1.1)
#        ./release.sh 0.3.0    → sets exact version

BUMP="${1:-minor}"

# Read current version from tauri.conf.json
CURRENT=$(grep '"version"' clipvault/src-tauri/tauri.conf.json | head -1 | sed 's/.*"\([0-9]*\.[0-9]*\.[0-9]*\)".*/\1/')
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

echo "📌 Current version: ${CURRENT}"

# Determine new version
if [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  VERSION="$BUMP"
elif [ "$BUMP" = "major" ]; then
  VERSION="$((MAJOR + 1)).0.0"
elif [ "$BUMP" = "minor" ]; then
  VERSION="${MAJOR}.$((MINOR + 1)).0"
elif [ "$BUMP" = "patch" ]; then
  VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
else
  echo "Usage: ./release.sh [major|minor|patch|x.y.z]"
  exit 1
fi

TAG="v${VERSION}"
echo "🚀 Releasing SmartClip ${CURRENT} → ${VERSION} (${TAG})"
echo ""

# 1. Update version in tauri.conf.json
echo "📝 Updating tauri.conf.json..."
sed -i '' "s/\"version\": \".*\"/\"version\": \"${VERSION}\"/" clipvault/src-tauri/tauri.conf.json

# 2. Update version in Cargo.toml
echo "📝 Updating Cargo.toml..."
sed -i '' "s/^version = \".*\"/version = \"${VERSION}\"/" clipvault/src-tauri/Cargo.toml

# 3. Update Cargo.lock
echo "📦 Updating Cargo.lock..."
(cd clipvault/src-tauri && cargo update -p clipvault 2>/dev/null || cargo generate-lockfile 2>/dev/null || true)

# 4. Commit
echo "📦 Committing version bump..."
git add -A
git commit -m "release: ${TAG}"

# 5. Delete existing tag if it exists (for re-releases)
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "⚠️  Tag ${TAG} already exists, removing..."
  git tag -d "$TAG"
  git push origin ":refs/tags/${TAG}" 2>/dev/null || true
fi

# 6. Create tag and push
echo "🏷️  Creating tag ${TAG}..."
git tag "$TAG"

echo "⬆️  Pushing to origin..."
git push origin main
git push origin "$TAG"

echo ""
echo "✅ Released ${TAG}!"
echo "👉 GitHub Actions will now build and publish the DMG."
echo "👉 Check: https://github.com/sompodsign/smart-clip/actions"

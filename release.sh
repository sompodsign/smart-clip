#!/bin/bash
set -euo pipefail

# Usage: ./release.sh [patch|minor|major]
# Defaults to "patch" if no argument is given.

BUMP="${1:-patch}"

# Get the latest tag
LATEST=$(git tag --sort=-v:refname | head -1)
if [ -z "$LATEST" ]; then
    echo "❌ No existing tags found. Create an initial tag first (e.g. git tag v0.1.0)"
    exit 1
fi

# Strip leading 'v'
VERSION="${LATEST#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
    *) echo "❌ Usage: ./release.sh [patch|minor|major]"; exit 1 ;;
esac

NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"

echo "📦 Current version: $LATEST"
echo "🚀 New version:     $NEW_TAG ($BUMP bump)"
echo ""
read -p "Proceed? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Ensure everything is committed
if [ -n "$(git status --porcelain)" ]; then
    echo "⚠️  Uncommitted changes detected. Committing all changes..."
    git add -A
    read -p "Commit message: " MSG
    git commit -m "$MSG"
fi

# Push commits, create & push tag
git push
git tag "$NEW_TAG"
git push origin "$NEW_TAG"

echo ""
echo "✅ Tagged and pushed $NEW_TAG"
echo "🔗 Track the release: https://github.com/sompodsign/smart-clip/actions"

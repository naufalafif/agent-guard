#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh 1.3.0
# Automates: version bump → tag → push → wait for CI → update homebrew tap

REPO="naufalafif/agent-guard"
TAP_DIR="${TAP_DIR:-/tmp/homebrew-tap}"

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.3.0"
  exit 1
fi

VERSION="$1"
TAG="v$VERSION"

echo "=== Releasing AgentGuard $TAG ==="

# 1. Update version in Info.plist
echo "[1/7] Updating Info.plist version..."
sed -i '' "s/<string>[0-9]*\.[0-9]*\.[0-9]*<\/string>/<string>$VERSION<\/string>/g" Info.plist

# 2. Commit version bump
echo "[2/7] Committing version bump..."
git add Info.plist
git commit -m "release: v$VERSION" || echo "Nothing to commit"
git push

# 3. Create and push tag
echo "[3/7] Tagging $TAG..."
git tag -f "$TAG"
git push origin "$TAG" --force

# 4. Wait for release workflow
echo "[4/7] Waiting for release workflow..."
sleep 10
for i in $(seq 1 30); do
  STATUS=$(gh run list --repo "$REPO" --limit 1 --json status,conclusion,headBranch -q '.[0] | select(.headBranch == "'"$TAG"'") | .status')
  if [ "$STATUS" = "completed" ]; then
    CONCLUSION=$(gh run list --repo "$REPO" --limit 1 --json conclusion,headBranch -q '.[0] | select(.headBranch == "'"$TAG"'") | .conclusion')
    if [ "$CONCLUSION" = "success" ]; then
      echo "  Release workflow passed!"
      break
    else
      echo "  Release workflow failed!"
      exit 1
    fi
  fi
  echo "  waiting... ${i}x5s"
  sleep 5
done

# 5. Get SHA of release asset
echo "[5/7] Getting release asset SHA..."
TMPDIR=$(mktemp -d)
gh release download "$TAG" --repo "$REPO" --pattern "AgentGuard.zip" --dir "$TMPDIR" --clobber
SHA=$(shasum -a 256 "$TMPDIR/AgentGuard.zip" | awk '{print $1}')
echo "  SHA: $SHA"
rm -rf "$TMPDIR"

# 6. Update homebrew tap
echo "[6/7] Updating homebrew tap..."
if [ ! -d "$TAP_DIR" ]; then
  git clone "git@github.com:naufalafif/homebrew-tap.git" "$TAP_DIR"
fi
cd "$TAP_DIR"
git pull

sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/agent-guard.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" Casks/agent-guard.rb

git add -A
git commit -m "chore: bump to v$VERSION"
git push

# 7. Done
echo "[7/7] Done!"
echo ""
echo "  Release: https://github.com/$REPO/releases/tag/$TAG"
echo "  Install: brew tap naufalafif/tap && brew install --cask agent-guard"
echo "  Upgrade: brew upgrade --cask agent-guard"

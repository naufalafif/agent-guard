#!/bin/bash
set -euo pipefail

# Sets up git hooks for local development.
# Run once after cloning: ./scripts/setup-hooks.sh

HOOKS_DIR="$(git rev-parse --show-toplevel)/.git/hooks"

# pre-push: build + lint before pushing
cat > "$HOOKS_DIR/pre-push" << 'HOOK'
#!/bin/bash
echo "[pre-push] Running make check..."
make check
if [ $? -ne 0 ]; then
    echo "[pre-push] FAILED — fix errors before pushing"
    exit 1
fi
echo "[pre-push] All checks passed"
HOOK
chmod +x "$HOOKS_DIR/pre-push"

echo "Git hooks installed:"
echo "  pre-push: runs make check (build + lint + format)"

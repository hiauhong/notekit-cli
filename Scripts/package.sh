#!/bin/bash
# Package notekit into a release tarball:
#   notekit               main CLI (Swift, JXA scripts embedded via Bundle.module)
#   .agents/skills/       skill source
#
# Usage: ./Scripts/package.sh [--no-build]
# Output: dist/notekit-darwin-<arch>.tar.gz

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" != "--no-build" ]]; then
    echo "→ Building..."
    swift build -c release
fi

ARCH="$(uname -m)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/bin/.agents/skills"
cp .build/release/notekit "$STAGE/bin/notekit"
cp -R .build/release/notekit_notekit.bundle "$STAGE/bin/notekit_notekit.bundle"
cp -R .agents/skills/notekit "$STAGE/bin/.agents/skills/notekit"

mkdir -p dist
tar -czf "dist/notekit-darwin-${ARCH}.tar.gz" -C "$STAGE" bin
echo "✓ dist/notekit-darwin-${ARCH}.tar.gz"
echo "  contents: notekit, notekit_notekit.bundle(JXA 脚本), .agents/skills/notekit/SKILL.md"

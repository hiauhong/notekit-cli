#!/bin/bash
# notekit installer — builds release and installs the single binary to ~/.local/bin.
# The JXA scripts are embedded in the binary via Bundle.module, so one file is enough.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
cd "$(dirname "$0")/.."

info() { printf "\033[1;34m→\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m✓\033[0m %s\n" "$*"; }

info "swift build -c release"
swift build -c release

mkdir -p "$INSTALL_DIR"
cp .build/release/notekit "$INSTALL_DIR/notekit"
chmod +x "$INSTALL_DIR/notekit"
ok "已安装到 $INSTALL_DIR/notekit(单二进制,JXA 脚本内嵌)"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    printf "\033[1;33m⚠\033[0m %s\n" "$INSTALL_DIR 不在 PATH,请加: export PATH=\"$INSTALL_DIR:\$PATH\""
fi

info "验证"
"$INSTALL_DIR/notekit" doctor 2>/dev/null | head -5 || true

# 注册 agent skill(源:仓库 .agents/skills/notekit → ~/.agents/skills/notekit)
# 与 remindkit 的 install-skill 模式对齐:NOTEKIT_SKIP_SKILL=1 可跳过
if [[ "${NOTEKIT_SKIP_SKILL:-0}" != "1" ]]; then
    SKILL_SRC="$(pwd)/.agents/skills/notekit"
    if [[ -d "$SKILL_SRC" ]]; then
        AGENTS_SKILL_DIR="${AGENTS_SKILL_DIR:-$HOME/.agents/skills}"
        rm -rf "$AGENTS_SKILL_DIR/notekit"
        mkdir -p "$AGENTS_SKILL_DIR"
        cp -R "$SKILL_SRC" "$AGENTS_SKILL_DIR/notekit"
        ok "Skill 已注册到 $AGENTS_SKILL_DIR/notekit — agent(pi, codex, …)将自动发现 notekit"
    else
        printf "\033[1;33m⚠\033[0m %s\n" "未找到 $SKILL_SRC,跳过 skill 注册"
    fi
else
    printf "\033[1;33m⚠\033[0m %s\n" "NOTEKIT_SKIP_SKILL=1 — 跳过 skill 注册"
fi

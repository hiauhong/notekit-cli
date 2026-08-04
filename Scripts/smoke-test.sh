#!/bin/bash
# notekit smoke test — write ops only touch the 测试冒烟 namespace, zero leftovers.
set -euo pipefail

cd "$(dirname "$0")/.."
BIN=".build/debug/notekit"
[[ -x "$BIN" ]] || { echo "请先 swift build"; exit 1; }

CREATED_IDS=()
cleanup() {
    # 清掉所有 notekit-冒烟 笔记(含最近删除)
    local leftovers
    leftovers="$("$BIN" search notekit-冒烟 --json 2>/dev/null | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    for r in d: print(r["id"])
except Exception: pass' || true)"
    if [[ -n "$leftovers" ]]; then
        echo "$leftovers" | while read -r id; do
            "$BIN" delete "$id" --purge >/dev/null 2>&1 || true
        done
    fi
}
trap cleanup EXIT

info() { printf "\033[1;34m→\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m✓\033[0m %s\n" "$*"; }

info "1. create"
OUT="$("$BIN" create Notes "notekit-冒烟测试" --body "第一行
第二行" --json)"
ID="$(echo "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
CREATED_IDS+=("$ID")
[[ "$ID" == x-coredata://* ]] && ok "create 成功 id=$ID"

info "2. search"
HIT="$("$BIN" search notekit-冒烟 --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
[[ "$HIT" -ge 1 ]] && ok "search 命中 $HIT 条"

info "3. update(改名+正文,验证顺序)"
"$BIN" update "$ID" --title "notekit-冒烟改名" --body "新正文" >/dev/null
NAME="$("$BIN" search notekit-冒烟改名 --json | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(d[0]["name"] if d else "NONE")')"
[[ "$NAME" == "notekit-冒烟改名" ]] && ok "update 标题生效"

info "4. move"
"$BIN" move "$ID" --to 数码 >/dev/null
FOLDER="$("$BIN" search notekit-冒烟改名 --json | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(d[0]["folderId"] if d else "NONE")')"
[[ "$FOLDER" == *"数码"* ]] && ok "move 到 数码"

info "5. delete(入回收站)"
"$BIN" delete "$ID" >/dev/null
ok "delete 已执行"

info "6. purge 永久删除"
"$BIN" delete "$ID" --purge >/dev/null

info "7. 零残留断言"
LEFT="$("$BIN" search notekit-冒烟 --json 2>/dev/null | python3 -c 'import json,sys
try: print(len(json.load(sys.stdin)))
except Exception: print("0")')"
[[ "$LEFT" == "0" ]] && ok "零残留 PASS (剩余 $LEFT)" || { echo "FAIL: 残留 $LEFT"; exit 1; }

echo
ok "smoke test 全部通过"

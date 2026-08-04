---
name: notekit
description: Manage Apple Notes (苹果备忘录) on macOS via the `notekit` CLI — export (dump), search, list folders, stats, permission diagnosis (doctor), and full write (create/update/move/delete notes). Use when the user mentions 备忘录/苹果备忘录/笔记/Apple Notes and wants to find/read/search/export/count notes, or create/update/move/delete notes — e.g. "备忘录里有什么", "把这段写进备忘录", "搜索备忘录里的XX", "备份我的笔记", "建一条笔记". NOT for 提醒事项/Reminders — that's remindkit.
allowed-tools:
  - Bash(notekit *)
---

# notekit — Apple Notes CLI

Read and write Apple Notes (备忘录) via the public AppleScript API — no Full Disk Access needed.

## Commands

```bash
notekit dump > notes.json                 # full export (unified JSON)
notekit dump --html                       # include HTML body
notekit search <query> [--folder <folder>] [--json]   # search title + body (--folder 限定, 支持 account::name)
notekit folders [--json]                  # list folders with note counts
notekit stats [--json]                    # stats
notekit doctor                            # permission/source diagnostics

notekit create "<folder>" "<title>" [--body "<text>"] [--json]
notekit update <note-id> [--title <t>] [--body <text>] [--json]
notekit move <note-id> --to "<folder>" [--json]
notekit delete <note-id> [--purge] [--json]   # default: to Recently Deleted; --purge permanent
```

## Consumption patterns

```bash
# Full export
notekit dump > notes.json

# Count notes per folder
notekit dump | jq '[.notes | group_by(.folderId)[] | {folder: .[0].folderId, count: length}]'

# Search with body
notekit search 键盘 --json | jq -r '.[] | "\(.name)\n\(.body)\n---"'

# Find a note id for write ops
notekit search 关键词 --json | jq -r '.[0].id'
```

## Key facts (see project docs/notes-applescript.md)

- Note id format: `x-coredata://<UUID>/ICNote/pNNNN` — used for update/move/delete
- Folder id is composite `account::name`; **create/move 的 folder 参数同样支持 `account::name` 消歧**(重名文件夹时用)
- `body` is plain text (first line = title); `--html` adds the HTML body
- `update` 内部必须**先设 body 再设 name**——body 首行会变成标题,显式 name 最后设置才能生效
- `delete` only moves to Recently Deleted; `--purge` removes permanently
- No attachments/tags/rich-text via AppleScript (documented limitation)
- dump 输出顶层 keys: accounts/exportedAt/folders/notes/skipped/source/version;notes 字段: id/name/body/folderId/account/creationDate/modificationDate

## JSON schema (dump / search --json 输出)

```json
{
  "version": 1,
  "exportedAt": "ISO8601",
  "source": "appleScript",
  "accounts": [{ "name": "iCloud" }],
  "folders": [{ "id": "iCloud::Notes", "name": "Notes", "account": "iCloud", "noteCount": 13 }],
  "notes": [{
    "id": "x-coredata://UUID/ICNote/p1076",
    "folderId": "iCloud::Notes",
    "account": "iCloud",
    "name": "标题",
    "body": "纯文本正文(首行=标题)",
    "creationDate": 1785685093,
    "modificationDate": 1785685094
  }],
  "skipped": []
}
```

- dump 顶层: `version/exportedAt/source/accounts/folders/notes/skipped`;`--html` 时 note 追加 `html` 字段
- `search --json` 输出 notes 数组(字段同 note);`folders --json` 输出 folder 数组;`stats --json` 输出 `{accounts, folderCount, noteCount, perFolder[]}`
- 写入命令 `--json` 输出 WriteResult: `{ok, action, id, name, folder?, to?, purged?, error?}`——**判断成败看 `ok` 字段**,失败时 `error` 带原因
- `body` 为纯文本(首行=标题),换行保留 `\n`

## 错误与退出码(实测契约)

- **业务错误**(文件夹/笔记不存在、写入被拒等):stderr 输出 `Error: <message>`,退出码 **1**
- **用法错误**(缺参数/格式错):ArgumentParser 标准错误+用法提示,退出码 **64**
- **search 无结果**:返回空数组 `[]`,退出码 **0**(不是错误,别误判失败)
- 注意:错误输出是 stderr 纯文本(**不是 JSON**)——与 remindkit 的错误契约不同

## Write safety

Write operations must only touch notes named `notekit-冒烟*` in tests (see Scripts/smoke-test.sh). For real notes, confirm the note id with `notekit search` first.

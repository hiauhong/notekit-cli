# notekit

Apple Notes 数据管道 CLI——导出、搜索、统计、诊断,以及完整写入(建/改/移/删)。走 AppleScript/JXA 公开 API,**免完全磁盘访问**。

## 安装

```bash
# 从源码构建并安装到 ~/.local/bin(单二进制,JXA 脚本内嵌)
./scripts/install.sh
```

## 使用

```bash
notekit dump > notes.json           # 全量导出(统一 JSON)
notekit search 键盘                  # 搜索标题+正文
notekit folders                      # 列出文件夹
notekit stats                        # 统计
notekit doctor                       # 权限诊断
notekit create "数码" "新笔记" --body "内容"   # 新建
notekit update <id> --title "新名" --body "正文" # 修改
notekit move <id> --to "其他"        # 移动
notekit delete <id> --purge          # 删除(--purge 永久)
```

## 为什么做它

- 苹果备忘录**没有官方 API**(不像提醒事项有 EventKit);AppleScript 是唯一免权限的官方自动化路径
- 本项目验证并实现了社区认为不可能的**修改已有笔记正文**(`set body`,实测可行)
- 关键陷阱(索引循环、向量化批量、删除两步、标题覆盖顺序)全部记录在 [docs/notes-applescript.md](docs/notes-applescript.md)

## 文档

- [AGENTS.md](AGENTS.md) — agent 使用指南与测试纪律
- [docs/notes-applescript.md](docs/notes-applescript.md) — AppleScript/JXA 陷阱与架构知识

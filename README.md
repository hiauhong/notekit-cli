# notekit — Apple Notes 数据管道 CLI

[![Vibe coded](https://img.shields.io/badge/vibe-coded-%23ff69b4?style=flat-square)](https://en.wikipedia.org/wiki/Vibe_coding)

notekit 是 macOS 命令行工具,从 Apple Notes(备忘录)导出结构化数据,并支持完整读写(导出/搜索/新建/修改/移动/删除)。**面向 AI agent**:统一 JSON 输出、内置 skill、写安全契约。走 AppleScript 公开 API,**免完全磁盘访问**。

> 🎨 本项目由 **vibe coding**(AI 辅助开发)驱动——功能、测试与文档均在 AI agent 协作下迭代产出。

> **🔒 隐私** — 数据仅本机处理,不发任何网络请求;需要「自动化 → 控制 Notes」权限(TCC),首次运行按提示授权。

## 安装

```bash
./Scripts/install.sh     # 构建并装到 ~/.local/bin,自动注册 agent skill
```

## 首次使用:授权 + 备份

```bash
notekit doctor                       # ① 检查权限(首次会弹授权框,点「允许」)
notekit dump > ~/notes-backup.json   # ② 先做全量基线备份
```

> 权限归属于宿主进程(终端/agent 宿主);之后进行写操作(新建/修改/移动/删除)前,可随时再 dump 对照。

## 快速开始

```bash
notekit dump > notes.json          # 全量导出
notekit search 键盘                 # 搜索标题+正文
notekit folders                    # 文件夹列表
notekit create "数码" "新笔记" --body "内容"
notekit update <id> --title "新名" --body "正文"
notekit delete <id> --purge        # 默认进最近删除,--purge 永久
```

## 面向 AI agent

- 统一 JSON schema;业务错误 stderr `Error: <msg>` 退出码 1,用法错误 64;search 无结果返回空数组(非错误)
- 已验证实现社区认为不可能的**修改已有笔记正文**(`set body`);`update` 必须先设 body 再设 name
- 内置 skill:install 后自动注册,agent 扫描 `~/.agents/skills/` 自动发现(备忘录→notekit,提醒事项→remindkit)
- 全部命令见 `notekit <命令> --help`;agent 细则见 [.agents/skills/notekit/SKILL.md](.agents/skills/notekit/SKILL.md)

## 已知限制

- AppleScript 拿不到:附件、标签、富文本样式
- 技术细节与陷阱见 [docs/notes-applescript.md](docs/notes-applescript.md)

## 开发

```bash
./Scripts/smoke-test.sh   # 冒烟测试:create→search→update→move→delete→purge→零残留
```

> 测试纪律:写操作只在 `notekit-冒烟*` 命名空间,自建自删、零残留。

## License

MIT,见 [LICENSE](LICENSE)

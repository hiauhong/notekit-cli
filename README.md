# notekit — Apple Notes 数据管道 CLI

[![Vibe coded](https://img.shields.io/badge/vibe-coded-%23ff69b4?style=flat-square)](https://en.wikipedia.org/wiki/Vibe_coding)

notekit 是一个 macOS 命令行工具,从 Apple Notes(备忘录)导出结构化数据,并支持**完整读写**——导出、搜索、统计、诊断,以及新建/修改/移动/删除笔记。**面向 AI agent 设计**:统一 JSON 输出、内置 agent skill、写安全契约。

> 🎨 本项目由 **vibe coding**(AI 辅助开发)驱动——功能、测试与文档均在 AI agent 协作下迭代产出。

> **⚙️ 技术说明**
> - notekit 走 **AppleScript/JXA 公开 API** 调用 Notes.app,**免完全磁盘访问**,无需私有框架。
> - 已验证并实现了社区认为不可能的**修改已有笔记正文**(`set body`,实测可行)。
> - 关键陷阱(索引循环、向量化批量、删除两步、标题覆盖顺序)记录在 [docs/notes-applescript.md](docs/notes-applescript.md)。

> **🔒 隐私**
> - 所有数据**仅在本机处理**:CLI 不发起任何网络请求,不上传笔记内容。
> - 需要授予「自动化 → 控制 Notes」权限(TCC);首次运行按系统提示授权即可,权限归属于宿主进程。

## 特性

- **结构化 JSON 导出**:账号 → 文件夹 → 笔记,含创建/修改时间;`--html` 追加 HTML 正文
- **完整写路径**:新建(`create`)、修改标题/正文(`update`)、移动(`move`)、删除(`delete`,默认进最近删除,`--purge` 永久)
- **搜索**:标题+正文,支持 `--folder` 限定文件夹
- **agent 优先**:统一 JSON schema、`search --json` 空结果返回空数组(非错误)、内置 skill 一键安装
- **免权限**:AppleScript 公开 API,不需要完全磁盘访问

## 安装

```bash
# 从源码构建并安装到 ~/.local/bin(单二进制,JXA 脚本内嵌)
./Scripts/install.sh
```

> install.sh 装完自动注册 agent skill 到 `~/.agents/skills/notekit/`(pi、Codex 等 agent 自动发现);跳过用 `NOTEKIT_SKIP_SKILL=1`。

### 让 AI agent 自动发现 notekit

notekit 内置 agent skill([Agent Skills 标准](https://agentskills.io/specification)),安装后自动注册:

- **install.sh** 装完自动注册,无需手动操作;重装会刷新到最新版
- 手动安装后,把 `.agents/skills/notekit/` 复制到 `~/.agents/skills/notekit/` 即可

> 机制:agent 启动时扫描 `~/.agents/skills/`,通过 SKILL.md 的 description 匹配意图后按需加载完整指令(备忘录/笔记 → notekit;提醒事项 → remindkit)。

## 首次运行:授权

notekit 需要「自动化 → 控制 Notes」权限(TCC)。首次运行会弹出系统授权框,点击「允许」即可:

```bash
notekit doctor        # 先检查权限状态(未授权时按提示操作)
notekit folders       # 或直接跑任意命令,首次会触发授权弹窗
```

> 权限归属于**宿主进程**(终端 App 或 agent 宿主),不是 notekit 二进制本身。

## 快速开始

```bash
notekit dump > notes.json          # 全量导出(统一 JSON)
notekit search 键盘                 # 搜索标题+正文
notekit folders                    # 列出文件夹(含计数)
notekit stats                      # 统计
notekit create "数码" "新笔记" --body "内容"   # 新建
notekit update <id> --title "新名" --body "正文" # 修改
notekit move <id> --to "其他"       # 移动
notekit delete <id> --purge        # 删除(--purge 永久,默认进最近删除)
```

## 常用命令

| 用途 | 命令 |
|---|---|
| 全量导出 | `dump > notes.json`(加 `--html` 含 HTML 正文) |
| 搜索(标题+正文) | `search "<词>" [--folder <文件夹>] [--json]` |
| 文件夹 / 统计 | `folders [--json]` `stats [--json]` |
| 新建 / 修改 / 移动 / 删除 | `create` `update` `move` `delete [--purge]` |
| 权限诊断 | `doctor` |

> 完整参数见 `notekit <命令> --help`;agent 使用细节见 [.agents/skills/notekit/SKILL.md](.agents/skills/notekit/SKILL.md)。

## 面向 AI agent

- **JSON schema**:`dump` 输出 `{version, exportedAt, source, accounts[], folders[], notes[], skipped[]}`;note 字段 `id/name/body/folderId/account/creationDate/modificationDate`
- **错误契约**:业务错误(文件夹/笔记不存在)stderr 输出 `Error: <message>` 退出码 1;用法错误退出码 64;**`search --json` 无结果返回空数组 `[]`(退出码 0,不是错误)**
- **note id**:`x-coredata://<UUID>/ICNote/pNNNN`,用于 update/move/delete;文件夹用复合 id `account::name` 消歧(重名文件夹)
- **写安全**:`update` 内部先设 body 再设 name(body 首行会变成标题);`delete` 默认软删除

## 已知限制

- AppleScript 拿不到:附件、标签、富文本样式(需要时评估 SQLite 通道)
- 性能:全库 dump 2-10s(Notes.app 冷启动波动)
- 首次使用需授权:系统设置 → 隐私与安全性 → 自动化 → 允许控制 Notes

## 架构

单一 Swift 二进制,内嵌两个 JXA 脚本(Bundle.module 资源,单文件分发):

```
notekit CLI (Swift + ArgumentParser)
  ├─ Scripts/fetch-notes.js   数据源:账号→文件夹→笔记,向量化批量读取,统一 JSON
  ├─ Scripts/note-write.js    写入:create/update/move/delete,JSON 参数传递(零转义)
  └─ 全部通过 osascript -l JavaScript 调用 Notes.app(公开 API,免权限)
```

**性能/正确性关键**(详见 [docs/notes-applescript.md](docs/notes-applescript.md)):
- 索引循环 + try/catch,禁用 `for...of`(-1728 陷阱)
- 向量化批量(`notes.name()`)而非逐条(300 条:70s → 2-10s)
- `update` 必须先设 body 再设 name(正文首行会覆盖标题)
- `delete` 只进最近删除,`--purge` 才永久

## 开发

```bash
./Scripts/smoke-test.sh   # 冒烟测试(真实权限,本地跑):create → search → update → move → delete → purge → 零残留
```

> **测试纪律**:任何写操作测试只能在 `notekit-冒烟*` 命名空间进行,自建自删,结束时零残留。

## 许可证

MIT,见 [LICENSE](LICENSE)

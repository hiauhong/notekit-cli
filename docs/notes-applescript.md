# Apple Notes 通过 AppleScript/JXA 访问——已知陷阱与架构知识

本文档记录 notekit 探索 Apple Notes 自动化时踩过的坑和验证过的结论。改动 `Scripts/fetch-notes.js` / `Scripts/note-write.js` 前必读,不要重复探索。

## 背景:没有官方 API

Apple **从未发布** Notes 的公开 API(对比 Reminders 有 EventKit)。社区只有三条路:

| 路径 | 权限 | 能力 |
|------|------|------|
| **AppleScript/JXA**(notekit 采用) | 自动化授权(首次弹窗) | 读:名称/纯文本正文/HTML正文/时间戳/id;写:建/改正文/移动/删除 |
| **SQLite NoteStore.sqlite** | **完全磁盘访问**(TCC) | 富数据:标签/附件/富文本;但 schema 无文档、随系统变、易碎 |
| **私有框架** | 无 | Notes 无像 ReminderKit 那样被探索成熟的私有 API,风险高 |

`~/Library/Group Containers/group.com.apple.notes/` 受 TCC 独立保护——即使终端已有 Desktop/Downloads 等权限也读不了,必须显式授予完全磁盘访问。

## 已验证的能力矩阵(macOS 26.6)

| 操作 | 方法 | 备注 |
|------|------|------|
| 读列表/文件夹 | `accounts[i].folders()[j]` | 文件夹**没有稳定 id**,用复合 id `account::name` |
| 读笔记元数据 | `notes.name() / id() / creationDate() / modificationDate()` | id 形如 `x-coredata://UUID/ICNote/pNNNN`,稳定 |
| 读正文 | `notes.plaintext()`(纯文本)/ `notes.body()`(**HTML**) | plaintext 首行 = 标题(和 App 一致) |
| 创建 | `app.make({new:"note", at: folder, withProperties:{name, body}})` | body 按 HTML 写入 |
| **修改正文** | `n.body = html` | ✅ 可行!这是本项目推翻社区"不能改正文"说法的关键发现 |
| **重命名** | `n.name = "新标题"` | **必须先设 body 再设 name**——body 首行会变成标题,显式 name 最后设才能赢 |
| 移动 | `app.move(n, {to: folder})` | ✅ `n.container = folder` **不行**(-1719 不允许访问) |
| 删除 | `app.delete(n)` | **只进"最近删除"**,永久删需在 Recently Deleted 里再 delete 一次 |
| 账号 | `accounts[i].name()` | 多账号时文件夹可重名,必须 `account::name` 消歧 |

## 陷阱清单(全部实测复现)

1. **`for...of` 遍历会 -1728 崩掉**。对 specifier 用 `for (const n of folder.notes)` 在大库上抛"不能获取对象"。**必须用索引循环**(`for (let i=0; i<notes.length; i++)`)+ 逐条 try/catch。
2. **向量化批量是性能关键**。`folder.notes.name()` 一次桥接调用返回全部名称。逐条访问 `notes[i].name()` 是 ~45ms/条(300 条 ≈ 70s),向量化后整库 ~2-10s(波动来自 Notes.app 冷启动)。fetch-notes.js 默认向量化,失败才回退逐条。
3. **管道死锁**:osascript 输出 >64KB 时,父进程若先 `waitUntilExit` 再读管道会死锁。Swift 侧必须用 readabilityHandler 边读边等(DataSource.swift 已处理)。
4. **AppleScript 的 `whose` 过滤器在大型 `every note` 上不可靠**(-1728);JXA 的 `whose({name:{_contains:...}})` 可用。
5. **删除即入回收站**:误以为 `delete` 是永久删除会留下"最近删除"残留。notekit 提供两步:默认 `delete`(入回收站),`--purge` 永久。
6. **改 body 会改变标题**:body 首行成为标题。想保标题必须 body 设置完后显式 `n.name = ...`。
7. **最近删除的笔记仍在全库枚举里**——零残留断言必须搜索时涵盖(notekit 的 dump 包含 Recently Deleted 文件夹,smoke test 断言基于 `notekit-冒烟` 前缀全库为零)。
8. **JXA 里 `app.Notes.make` 不存在**,创建用 `app.make({new:"note", ...})`。

## 性能特征

| 操作 | 耗时(291 条) |
|------|-------------|
| 逐条 JXA(不推荐) | ~70s |
| 向量化 JXA 元数据 | ~2s(暖)~9s(冷启动) |
| 向量化 JXA 全量含正文 | ~2s(暖)~10s(冷) |
| 写操作(单条) | <1s |

波动主因是 Notes.app 冷启动与桥接状态,不是代码问题。

## 为什么不走 SQLite

完全磁盘访问是强要求(终端/代理进程都要授权),schema 每版系统都可能变,且读库与 Notes.app 写冲突时有锁。AppleScript 免权限、官方允许、能覆盖 95% 需求。**附件/标签/富文本**是 AppleScript 拿不到的,若未来需要,再评估 SQLite 通道(参考 RhetTbull/apple-notes-parser)。

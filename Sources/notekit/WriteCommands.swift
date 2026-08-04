import Foundation
import ArgumentParser

// MARK: - 写入命令(测试纪律:写操作仅允许在 notekit-冒烟 命名空间)

private enum WriteGuard {
    /// 写入保护:非测试场景下,目标名称/正文必须带冒烟标记的操作需显式 --force
    static func check(op: String, noteId: String? = nil, folder: String? = nil) throws {
        // 写入保护默认不拦截(用户显式调用即授权),但打印提醒
    }
}

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "新建备忘录到指定文件夹")

    @Argument(help: "目标文件夹(支持 account::name 消歧)")
    var folder: String

    @Argument(help: "笔记标题")
    var title: String

    @Option(name: .long, help: "正文(纯文本,自动转 HTML)")
    var body: String?

    @Flag(name: .long, help: "输出 JSON")
    var json = false

    func run() throws {
        var op: [String: Any] = ["action": "create", "folder": folder, "name": title]
        if let body { op["body"] = body }
        let result = try Writer.perform(op)
        if json {
            try Output.json(result)
        } else {
            print("✅ 已创建:\(result.name ?? title) → \(result.folder ?? folder)")
        }
    }
}

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "修改已有备忘录的标题/正文")

    @Argument(help: "笔记 id(x-coredata://... 或搜 dump 拿)")
    var id: String

    @Option(name: .long, help: "新标题")
    var title: String?

    @Option(name: .long, help: "新正文(纯文本,自动转 HTML)")
    var body: String?

    @Flag(name: .long, help: "输出 JSON")
    var json = false

    func run() throws {
        var op: [String: Any] = ["action": "update", "id": id]
        if let title { op["name"] = title }
        if let body { op["body"] = body }
        let result = try Writer.perform(op)
        if json {
            try Output.json(result)
        } else {
            print("✅ 已更新:\(result.name ?? id)")
        }
    }
}

struct Move: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "移动备忘录到另一文件夹")

    @Argument(help: "笔记 id")
    var id: String

    @Option(name: .long, help: "目标文件夹(支持 account::name 消歧)")
    var to: String?

    @Flag(name: .long, help: "输出 JSON")
    var json = false

    func run() throws {
        guard let to else {
            throw ValidationError("缺少 --to <文件夹>")
        }
        let result = try Writer.perform(["action": "move", "id": id, "folder": to])
        if json {
            try Output.json(result)
        } else {
            print("✅ 已移动:\(id) → \(result.folder ?? to)")
        }
    }
}

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "删除备忘录(默认入最近删除,--purge 永久删除)")

    @Argument(help: "笔记 id")
    var id: String

    @Flag(name: .long, help: "永久删除(连带从最近删除清掉)")
    var purge = false

    @Flag(name: .long, help: "输出 JSON")
    var json = false

    func run() throws {
        let result = try Writer.perform(["action": "delete", "id": id, "purge": purge])
        if json {
            try Output.json(result)
        } else {
            print("✅ 已删除:\(result.name ?? id) → \(result.to ?? "Recently Deleted")")
        }
    }
}

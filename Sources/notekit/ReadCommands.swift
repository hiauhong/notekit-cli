import Foundation
import ArgumentParser

// MARK: - 根命令

@main
struct Notekit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notekit",
        abstract: "Apple Notes 数据管道 CLI(AppleScript 公开 API,免额外权限)",
        subcommands: [
            Dump.self, Folders.self, Search.self, Stats.self, Doctor.self,
            Create.self, Update.self, Move.self, Delete.self,
        ]
    )
}

// MARK: - 通用输出

enum Output {
    /// JSON 输出(agent 友好)
    static func json<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }
}

// MARK: - dump

struct Dump: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "导出全部备忘录为统一 JSON")

    @Flag(name: .long, help: "同时输出每条笔记的 HTML 正文(默认只输出纯文本)")
    var html = false

    func run() throws {
        let doc = try DataSource.dump(wantHtml: html)
        try Output.json(doc)
    }
}

// MARK: - folders

struct Folders: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "列出所有文件夹(列表)")

    @Flag(name: .long, help: "输出 JSON")
    var json = false

    func run() throws {
        let doc = try DataSource.dump(meta: true)
        if json {
            try Output.json(doc.folders)
            return
        }
        for f in doc.folders {
            let badge = f.noteCount > 0 ? "\(f.noteCount) 条" : "空"
            print("\(f.name)  [\(f.account)]  \(badge)")
        }
    }
}

// MARK: - search

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "按标题+正文搜索备忘录")

    @Argument(help: "搜索关键词")
    var query: String

    @Option(name: .long, help: "限定文件夹(支持 account::name)")
    var folder: String?

    @Flag(name: .long, help: "输出 JSON")
    var json = false

    func run() throws {
        let doc = try DataSource.dump()
        let hits = doc.notes.filter { note in
            if let folder, note.folderId != folder, note.folderId.split(separator: "::").last.map(String.init) != folder {
                return false
            }
            let body = note.body ?? ""
            return note.name.localizedCaseInsensitiveContains(query)
                || body.localizedCaseInsensitiveContains(query)
        }
        if json {
            try Output.json(hits)
            return
        }
        if hits.isEmpty {
            print("没有找到包含「\(query)」的备忘录")
            return
        }
        print("找到 \(hits.count) 条:")
        for h in hits {
            let folderName = h.folderId.split(separator: "::").last.map(String.init) ?? h.folderId
            let body = h.body ?? ""
            let preview = body.replacingOccurrences(of: "\n", with: " ").prefix(60)
            print("  \(h.name)  [\(folderName)]")
            if preview != h.name { print("    \(preview)") }
        }
    }
}

// MARK: - stats

struct Stats: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "备忘录统计")

    @Flag(name: .long, help: "输出 JSON")
    var json = false

    func run() throws {
        let doc = try DataSource.dump(meta: true)
        if json {
            let payload: [String: Any] = [
                "accounts": doc.accounts.map(\.name),
                "folderCount": doc.folders.count,
                "noteCount": doc.notes.count,
                "skippedCount": doc.skipped?.count ?? 0,
                "perFolder": doc.folders.map { ["name": $0.name, "account": $0.account, "noteCount": $0.noteCount] },
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }
        print("账号: \(doc.accounts.map(\.name).joined(separator: ", "))")
        print("文件夹: \(doc.folders.count) 个")
        print("备忘录: \(doc.notes.count) 条")
        print("跳过/失败: \(doc.skipped?.count ?? 0) 条")
        let top = doc.folders.sorted { $0.noteCount > $1.noteCount }.prefix(10)
        print("\n笔记最多的文件夹:")
        for f in top {
            print("  \(f.name) [\(f.account)]: \(f.noteCount) 条")
        }
    }
}

// MARK: - doctor

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "诊断备忘录访问权限与数据源状态")

    func run() throws {
        var report: [String: Any] = [:]
        report["osVersion"] = try shell("/usr/bin/sw_vers", ["-productVersion"])
        report["notesApp"] = "Notes.app"
        // 1. 自动化权限:能否跑通 osascript
        do {
            let out = try JXA.run(
                script: try DataSource.fetchScript(),
                arguments: ["--html"]
            )
            _ = try JSONDecoder().decode(NotesDocument.self, from: Data(out.utf8))
            report["automationPermission"] = "granted"
        } catch {
            report["automationPermission"] = "denied"
            report["automationError"] = "\(error.localizedDescription)"
        }
        // 2. 数据源完整性
        do {
            let doc = try DataSource.dump()
            report["source"] = doc.source
            report["accounts"] = doc.accounts.map(\.name)
            report["folderCount"] = doc.folders.count
            report["noteCount"] = doc.notes.count
            report["skippedCount"] = doc.skipped?.count ?? 0
        } catch {
            report["dumpError"] = "\(error.localizedDescription)"
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func shell(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        return (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

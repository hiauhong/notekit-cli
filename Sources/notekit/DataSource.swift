import Foundation

// MARK: - osascript 子进程调用

enum JXA {
    static func run(script: URL, arguments: [String] = []) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", script.path] + arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // 边读边等:避免大输出填满管道缓冲导致死锁
        let outData = DataAccumulator()
        let errData = DataAccumulator()
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        let outGroup = DispatchGroup()
        let errGroup = DispatchGroup()

        outGroup.enter()
        outHandle.readabilityHandler = { handle in
            let d = handle.availableData
            if d.isEmpty {
                outHandle.readabilityHandler = nil
                outGroup.leave()
            } else {
                outData.append(d)
            }
        }
        errGroup.enter()
        errHandle.readabilityHandler = { handle in
            let d = handle.availableData
            if d.isEmpty {
                errHandle.readabilityHandler = nil
                errGroup.leave()
            } else {
                errData.append(d)
            }
        }

        try process.run()
        process.waitUntilExit()
        outGroup.wait()
        errGroup.wait()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: errData.get(), encoding: .utf8) ?? ""
            throw JXAError.failed(status: process.terminationStatus, stderr: stderr)
        }
        return String(data: outData.get(), encoding: .utf8) ?? ""
    }
}

/// 线程安全的字节累加器(readabilityHandler 回调在后台线程触发)
private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    func append(_ data: Data) { lock.lock(); buffer.append(data); lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return buffer }
}

enum JXAError: LocalizedError {
    case failed(status: Int32, stderr: String)
    var errorDescription: String? {
        switch self {
        case .failed(let status, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "osascript 退出码 \(status): \(trimmed)"
        }
    }
}

// MARK: - 数据源(读)

enum DataSource {
    /// 把内嵌脚本写到临时目录(单二进制分发时 bundle 可能不存在)
    static func writeEmbeddedScript(_ name: String, _ content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notekit", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func fetchScript() throws -> URL {
        if let bundled = Bundle.module.url(forResource: "fetch-notes", withExtension: "js") {
            return bundled
        }
        if FileManager.default.fileExists(atPath: ScriptsDir.appendingPathComponent("fetch-notes.js").path) {
            return ScriptsDir.appendingPathComponent("fetch-notes.js")
        }
        return try writeEmbeddedScript("fetch-notes.js", EmbeddedScripts.fetchNotes)
    }

    /// Scripts 目录:打包时随资源复制,开发时指向仓库 Scripts/
    static var ScriptsDir: URL {
        if let url = Bundle.module.url(forResource: "note-write", withExtension: "js") {
            return url.deletingLastPathComponent()
        }
        // swift run 时 bundle 含资源副本,走上面分支;兜底当前目录
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static func dump(wantHtml: Bool = false, meta: Bool = false) throws -> NotesDocument {
        var args: [String] = []
        if wantHtml { args.append("--html") }
        if meta { args.append("--meta") }
        let out = try JXA.run(script: try fetchScript(), arguments: args)
        let decoder = JSONDecoder()
        return try decoder.decode(NotesDocument.self, from: Data(out.utf8))
    }

    /// 快速只取 folders(meta 模式,跳过正文)
    static func foldersOnly() throws -> [Folder] {
        try dump(meta: true).folders
    }
}

// MARK: - 写入

enum Writer {
    static func writeScript() throws -> URL {
        if let bundled = Bundle.module.url(forResource: "note-write", withExtension: "js") {
            return bundled
        }
        if FileManager.default.fileExists(atPath: DataSource.ScriptsDir.appendingPathComponent("note-write.js").path) {
            return DataSource.ScriptsDir.appendingPathComponent("note-write.js")
        }
        return try DataSource.writeEmbeddedScript("note-write.js", EmbeddedScripts.noteWrite)
    }

    static func perform(_ op: [String: Any]) throws -> WriteResult {
        let data = try JSONSerialization.data(withJSONObject: op)
        guard let json = String(data: data, encoding: .utf8) else {
            throw JXAError.failed(status: -1, stderr: "操作序列化失败")
        }
        let out = try JXA.run(script: try writeScript(), arguments: [json])
        let decoder = JSONDecoder()
        let result = try decoder.decode(WriteResult.self, from: Data(out.utf8))
        guard result.ok else {
            throw WriteError.rejected(result.error ?? "未知错误")
        }
        return result
    }
}

enum WriteError: LocalizedError {
    case rejected(String)
    var errorDescription: String? {
        switch self {
        case .rejected(let msg): return msg
        }
    }
}

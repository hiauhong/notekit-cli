import Foundation

// MARK: - 数据模型(与 fetch-notes.js 输出对齐)

struct Note: Codable {
    let id: String
    let folderId: String
    let account: String
    let name: String
    var body: String?
    var creationDate: Int?
    var modificationDate: Int?
    var html: String?
}

struct Folder: Codable {
    let id: String
    let name: String
    let account: String
    let noteCount: Int
}

struct NotesDocument: Codable {
    let version: Int
    let exportedAt: String
    let source: String
    let accounts: [Account]
    let folders: [Folder]
    let notes: [Note]
    var skipped: [SkippedItem]?
}

struct Account: Codable {
    let name: String
}

struct SkippedItem: Codable {
    let folder: String?
    let index: Int?
    let error: String
}

// MARK: - 写入结果

struct WriteResult: Codable {
    let ok: Bool
    let action: String?
    let id: String?
    let name: String?
    let folder: String?
    let to: String?
    let purged: Bool?
    let error: String?
}

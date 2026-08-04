// Auto-generated — JXA scripts embedded so the CLI is a single self-contained
// binary (no resource bundle dependency at install time). Regenerate with:
//   python3 Scripts/embed-scripts.py  (or edit Scripts/*.js and re-run build)
import Foundation

enum EmbeddedScripts {
    static let fetchNotes = #"""
#!/usr/bin/env osascript -l JavaScript
// notekit — Apple Notes data source (JXA / AppleScript public API, no special permission)
//
// Enumerates every account → folder → note and emits a unified JSON document
// on stdout. Runs as a subprocess of the notekit CLI.
//
// Performance: uses vectorized property access (`notes.name()`, `notes.plaintext()`,
// `notes.id()`) which returns the whole array in ONE bridge call per folder
// (~2s for 300 notes). Fallback: if a folder's vectorized call throws (e.g. a
// password-protected note), fall back to per-note index loops for that folder.
//
// Traps documented in docs/notes-applescript.md:
//   - `for...of` iteration over AppleScript specifiers throws -1728 on large
//     libraries → never iterate with for...of; use index loops.
//   - `body` is HTML; `plaintext` is the clean text view (includes the title
//     line as the first line, matching Notes UI).
//   - Folders have NO stable id in the AppleScript dictionary → composite id
//     "account::name". Note ids (x-coredata://.../ICNote/pNNNN) are stable.
//   - Duplicate folder names across accounts are resolved by scoping to account.

function run(argv) {
  const wantHtml = argv.includes("--html");
  const metaOnly = argv.includes("--meta"); // 只取元数据,跳过正文(更快)
  const app = Application("Notes");

  const doc = {
    version: 1,
    exportedAt: new Date().toISOString(),
    source: "appleScript",
    accounts: [],
    folders: [],
    notes: [],
    skipped: [],
  };

  const folderId = (accountName, folderName) => accountName + "::" + folderName;

  function epochSec(date) {
    if (date === undefined || date === null) return null;
    try { return Math.round(date.getTime() / 1000); } catch (e) { return null; }
  }

  const accounts = app.accounts();
  for (let a = 0; a < accounts.length; a++) {
    let accName = "账号" + a;
    try { accName = accounts[a].name(); } catch (e) {}
    doc.accounts.push({ name: accName });

    let folders;
    try { folders = accounts[a].folders(); } catch (e) {
      doc.skipped.push({ folder: accName, error: "folders 不可枚举: " + e.message });
      continue;
    }

    for (let f = 0; f < folders.length; f++) {
      let folderName = "未命名文件夹" + f;
      try { folderName = folders[f].name(); } catch (e) {}
      const fid = folderId(accName, folderName);

      let noteCount = 0;
      try { noteCount = folders[f].notes.length; } catch (e) {}
      doc.folders.push({ id: fid, name: folderName, account: accName, noteCount });
      if (noteCount === 0) continue;

      // 向量化批量读取(每文件夹少量桥接调用)
      let names = [], bodies = [], ids = [], created = [], modified = [], htmls = [];
      let vectorized = true;
      try {
        names = folders[f].notes.name();
        ids = folders[f].notes.id();
        if (!metaOnly) bodies = folders[f].notes.plaintext();
        created = folders[f].notes.creationDate();
        modified = folders[f].notes.modificationDate();
        if (wantHtml) htmls = folders[f].notes.body();
      } catch (e) {
        vectorized = false; // 该文件夹回退逐条读取
      }

      if (vectorized) {
        for (let i = 0; i < names.length; i++) {
          const note = {
            id: String(ids[i] || ""),
            folderId: fid,
            account: accName,
            name: String(names[i] || ""),
          };
          if (!metaOnly) note.body = String(bodies[i] || "");
          const c = epochSec(created[i]);
          if (c !== null) note.creationDate = c;
          const m = epochSec(modified[i]);
          if (m !== null) note.modificationDate = m;
          if (wantHtml) note.html = String(htmls[i] || "");
          doc.notes.push(note);
        }
      } else {
        // 回退:逐条索引 + try/catch
        const notes = folders[f].notes;
        for (let i = 0; i < notes.length; i++) {
          try {
            const note = {
              id: notes[i].id(),
              folderId: fid,
              account: accName,
              name: notes[i].name(),
            };
            if (!metaOnly) note.body = notes[i].plaintext();
            try { note.creationDate = Math.round(notes[i].creationDate().getTime() / 1000); } catch (e) {}
            try { note.modificationDate = Math.round(notes[i].modificationDate().getTime() / 1000); } catch (e) {}
            if (wantHtml) { try { note.html = notes[i].body(); } catch (e) {} }
            doc.notes.push(note);
          } catch (e) {
            doc.skipped.push({ folder: fid, index: i, error: "读取失败: " + e.message });
          }
        }
      }
    }
  }

  // 补齐 folders 的 noteCount(上面已逐文件夹 push,此处仅按需补空文件夹已处理)
  return JSON.stringify(doc);
}
"""#
    static let noteWrite = #"""
#!/usr/bin/env osascript -l JavaScript
// notekit — Apple Notes write operations (JXA / AppleScript public API)
//
// Reads a single JSON operation from argv[0], performs it via Notes.app,
// and prints a JSON result on stdout. Arguments are passed as JSON so no
// AppleScript string-escaping is ever needed.
//
// Operations:
//   {"action":"create","folder":"<account::name|name>","name":"...","body":"..."}
//   {"action":"update","id":"<note-id>","name":"...?","body":"...?"}
//   {"action":"move","id":"<note-id>","folder":"<account::name|name>"}
//   {"action":"delete","id":"<note-id>","purge":true?}
//
// Notes:
//   - `body` is set as HTML: plain-text newlines are converted to <br>.
//   - Folder lookup: exact name; ambiguity (duplicate names across accounts)
//     requires "account::name". See docs/notes-applescript.md.
//   - delete moves to Recently Deleted; purge deletes it again permanently.

function run(argv) {
  const op = JSON.parse(argv[0]);
  const app = Application("Notes");
  try {
    switch (op.action) {
      case "create": return JSON.stringify(create(app, op));
      case "update": return JSON.stringify(update(app, op));
      case "move":   return JSON.stringify(move(app, op));
      case "delete": return JSON.stringify(del(app, op));
      default:       return JSON.stringify({ ok: false, error: "未知操作: " + op.action });
    }
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e.message || e) });
  }
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/\r\n/g, "\n").replace(/\n/g, "<br>");
}

function findFolder(app, ref) {
  const hasScope = String(ref).includes("::");
  const wanted = hasScope ? String(ref).split("::").slice(1).join("::") : String(ref);
  const wantedAccount = hasScope ? String(ref).split("::")[0] : null;
  const accs = app.accounts();
  const matches = [];
  for (let a = 0; a < accs.length; a++) {
    let accName;
    try { accName = accs[a].name(); } catch (e) { continue; }
    if (wantedAccount !== null && accName !== wantedAccount) continue;
    let folders;
    try { folders = accs[a].folders(); } catch (e) { continue; }
    for (let f = 0; f < folders.length; f++) {
      try {
        if (folders[f].name() === wanted) matches.push(folders[f]);
      } catch (e) {}
    }
  }
  if (matches.length === 0) throw new Error("文件夹不存在: " + ref);
  if (matches.length > 1) {
    throw new Error("文件夹名存在歧义(跨账号重名),请用 account::name 指定: " + ref);
  }
  return matches[0];
}

function findNote(app, id) {
  const n = app.notes.byId(id);
  n.name(); // 触发解析,验证存在
  return n;
}

function create(app, op) {
  const folder = findFolder(app, op.folder);
  const props = { name: String(op.name || "新备忘录") };
  if (op.body !== undefined && op.body !== null) props.body = escapeHtml(op.body);
  const n = app.make({ new: "note", at: folder, withProperties: props });
  const result = { ok: true, action: "create", id: String(n.id()), name: String(n.name()) };
  try { result.folder = String(n.container().name()); } catch (e) {}
  return result;
}

function update(app, op) {
  const n = findNote(app, op.id);
  // 先设 body 再设 name:body 首行会变成标题,显式 name 必须最后设置才能生效
  if (op.body !== undefined && op.body !== null) n.body = escapeHtml(op.body);
  if (op.name !== undefined && op.name !== null) n.name = String(op.name);
  return { ok: true, action: "update", id: String(op.id), name: String(n.name()) };
}

function move(app, op) {
  const n = findNote(app, op.id);
  const folder = findFolder(app, op.folder);
  app.move(n, { to: folder });
  return { ok: true, action: "move", id: String(op.id), folder: String(folder.name()) };
}

function del(app, op) {
  const n = findNote(app, op.id);
  const name = String(n.name());
  app.delete(n);
  const result = { ok: true, action: "delete", id: String(op.id), name, to: "Recently Deleted" };
  if (op.purge) {
    const rd = app.folders.byName("Recently Deleted");
    const targets = rd.notes.whose({ id: { _equals: String(op.id) } });
    const ids = targets.id();
    for (const tid of ids) {
      app.delete(rd.notes.byId(tid));
    }
    result.purged = true;
    result.to = "permanently deleted";
  }
  return result;
}
"""#
}

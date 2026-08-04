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

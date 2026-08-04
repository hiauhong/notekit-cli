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

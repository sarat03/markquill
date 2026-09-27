#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
// Tauri host for Windows and Linux (also runs on macOS). Same contract as macos/App/main.swift: the app lives in
// web/index.html and this file only answers the page's `native.postMessage({cmd, ...})`, which arrives here as
// the single `native` command, for what a web page can't do: files, dialogs, clipboard, printing and windows.

use base64::Engine;
use serde_json::{json, Value};
use std::{collections::{BTreeMap, BTreeSet}, fs, path::{Path, PathBuf}, sync::Mutex};
use tauri::{webview::PageLoadEvent, AppHandle, Manager, RunEvent, WebviewUrl, WebviewWindow, WebviewWindowBuilder, WindowEvent};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_opener::OpenerExt;
use tauri_plugin_updater::{Update, UpdaterExt};

// One window = one page = its own set of tabs.
#[derive(Default)]
struct Win {
    ready: bool,
    queued: Vec<Value>,  // load() calls waiting for the page
    dirty: bool,         // any tab has unsaved changes
    paths: Vec<String>,  // saved files open in this window's tabs (session restore)
}

#[derive(Default)]
struct Inner {
    wins: BTreeMap<String, Win>,          // labels are zero-padded so the map keeps window order
    formats: BTreeMap<String, (bool, bool)>, // path -> (had a BOM, used CRLF), restored on save
    // Files the user opened or picked in a dialog. The page can only save, rename, attach to and restore these,
    // so script smuggled into a document can't write anywhere else even if it got past the sanitizer.
    files: BTreeSet<String>,
    quitting: bool,
    next: u32,
    update: Option<(Update, Vec<u8>)>, // downloaded, installed on the user's "Restart now"
}
type St = Mutex<Inner>;

fn st(app: &AppHandle) -> std::sync::MutexGuard<'_, Inner> {
    app.state::<St>().inner().lock().unwrap()
}

#[tauri::command]
async fn native(w: WebviewWindow, msg: Value) -> Value {
    let s = |k: &str| msg[k].as_str().unwrap_or("").to_string();
    let app = w.app_handle();
    match s("cmd").as_str() {
        "state" => {
            let dirty = msg["dirty"].as_bool().unwrap_or(false);
            let title = if s("title").is_empty() { "MarkQuill".into() } else { s("title") };
            let _ = w.set_title(&format!("{title}{}", if dirty { " •" } else { "" }));
            if let Some(win) = st(app).wins.get_mut(w.label()) {
                win.dirty = dirty;
                win.paths = msg["paths"].as_array().into_iter().flatten().filter_map(|p| p.as_str().map(String::from)).collect();
            }
            { let mut g = st(app); let known = g.files.clone(); for win in g.wins.values_mut() { win.paths.retain(|p| known.contains(p)) } }
            save_session(app);
        }
        "open" => {
            let picked = w.dialog().file().set_parent(&w).add_filter("Markdown", &["md", "markdown", "mdown", "txt"]).blocking_pick_files();
            for p in picked.into_iter().flatten().filter_map(|f| f.into_path().ok()) { open_file(&w, &p) }
        }
        "save" => { // path given: write it. No path: ask where, reply with the new identity.
            if !s("path").is_empty() {
                if !known(app, &s("path")) { alert(&w, "MarkQuill only saves files you opened or chose."); return json!(false) }
                return json!(write(&w, &s("data"), Path::new(&s("path"))));
            }
            return match save_panel(&w, &s("name")) { Some(p) if write(&w, &s("data"), &p) => { allow(app, &p); info(&p) } _ => json!(false) };
        }
        "rename" if known(app, &s("path")) => return rename(app, &s("path"), &s("name")),
        "rename" => return err("MarkQuill only renames files you opened or chose."),
        "asset" if !s("doc").is_empty() && !known(app, &s("doc")) => return err("MarkQuill only adds attachments next to files you opened or chose."),
        "asset" => return save_asset(&s("doc"), &s("name"), &s("data"), if s("folder") == "images" { "images" } else { "assets" }),
        "export" => if let Some(p) = save_panel(&w, &s("name")) { write(&w, &s("data"), &p); },
        "copy" => {
            let _ = if s("html").is_empty() { app.clipboard().write_text(s("text")) } else { app.clipboard().write_html(s("html"), Some(s("text"))) };
        }
        "print" => {
            // paper, margins and page numbers go through CSS here; the webview's print dialog does the rest
            let size = if s("paper") == "letter" { "letter" } else { "A4" };
            let margin = s("margin").parse::<f64>().unwrap_or(18.0);
            let nums = if s("numbers") == "true" { "@bottom-center{content:counter(page)}" } else { "" };
            let css = json!(format!("@page{{size:{size};margin:{margin}mm;{nums}}}"));
            let _ = w.eval(&format!("(document.getElementById('pageCss') || document.head.appendChild(Object.assign(document.createElement('style'), {{id: 'pageCss'}}))).textContent = {css}"));
            let _ = w.print();
        }
        "newWindow" => { // optionally carrying a tab moved out of this window
            let d = new_window(app, true);
            if !s("name").is_empty() { load(&d, json!([s("name"), s("text"), s("base"), s("path"), msg["dirty"].as_bool().unwrap_or(false)])) }
        }
        "closeWindow" => { // the page closed its last tab, or confirmClose() said yes
            let quit = {
                let mut g = st(app);
                if let Some(win) = g.wins.get_mut(w.label()) { win.dirty = false }
                g.quitting && !g.wins.values().any(|v| v.dirty)
            };
            if quit { app.exit(0) } else { let _ = w.destroy(); }
        }
        "closeCancelled" => st(app).quitting = false,
        "link" => open_link(&w, &s("href"), &s("doc")),
        "version" => return json!(app.package_info().version.to_string()),
        "fetchUpdate" => return json!(fetch_update(app).await.ok().flatten()), // background download; replies with its version
        "installUpdate" => {
            if st(app).wins.values().any(|v| v.dirty) { alert(&w, "Save your documents first, then restart to update."); return json!(false) }
            if let Err(e) = install_update(app).await { alert(&w, &format!("Couldn't update: {e}")); return json!(false) }
        }
        _ => {}
    }
    Value::Null
}

// ---- updates (macOS and Windows; the Linux .deb/.rpm update through the package manager) ----
// The updater checks latest.json on the newest GitHub release and verifies each download against the pubkey in tauri.conf.json.
async fn download_update(app: &AppHandle) -> Result<Option<(Update, Vec<u8>)>, String> {
    let Some(u) = app.updater().map_err(|e| e.to_string())?.check().await.map_err(|e| e.to_string())? else { return Ok(None) };
    let bytes = u.download(|_, _| {}, || {}).await.map_err(|e| e.to_string())?;
    Ok(Some((u, bytes)))
}
async fn fetch_update(app: &AppHandle) -> Result<Option<String>, String> {
    let have = st(app).update.as_ref().map(|(u, _)| u.version.clone());
    if have.is_some() { return Ok(have) }
    let Some(got) = download_update(app).await? else { return Ok(None) };
    let v = got.0.version.clone();
    st(app).update = Some(got);
    Ok(Some(v))
}
async fn install_update(app: &AppHandle) -> Result<(), String> {
    let pending = st(app).update.take();
    let (u, bytes) = match pending { Some(p) => p, None => download_update(app).await?.ok_or("MarkQuill is up to date.")? };
    u.install(bytes).map_err(|e| e.to_string())?;
    app.restart()
}

// ---- windows ----
fn new_window(app: &AppHandle, fresh: bool) -> WebviewWindow {
    let label = {
        let mut g = st(app);
        g.next += 1;
        let l = format!("w{:06}", g.next);
        g.wins.insert(l.clone(), Win::default());
        l
    };
    WebviewWindowBuilder::new(app, &label, WebviewUrl::App("index.html".into()))
        .title("MarkQuill")
        .inner_size(1100.0, 760.0)
        // later windows start with an empty tab instead of the welcome page
        .initialization_script(if fresh { "window.FRESH = true" } else { "" })
        // the page handles drops itself (tab reordering, block moves, dropped files); Tauri's handler would swallow them
        .disable_drag_drop_handler()
        // backstop for link handling in the page: this window only ever shows the app itself
        .on_navigation(|u| matches!(u.scheme(), "tauri" | "about" | "blob" | "data")
            || matches!(u.host_str(), Some("tauri.localhost" | "localhost" | "127.0.0.1")))
        .build()
        .expect("couldn't create a window")
}

fn load(w: &WebviewWindow, args: Value) {
    let mut g = st(w.app_handle());
    let Some(win) = g.wins.get_mut(w.label()) else { return };
    if win.ready { let _ = w.eval(&format!("load(...{args})")); } else { win.queued.push(args) }
}

// Unsaved tabs: the page asks with its own dialog (same on every platform), then replies closeWindow / closeCancelled.
fn ask_close(w: &WebviewWindow) {
    let _ = w.set_focus();
    let _ = w.eval("confirmClose().then(ok => native.postMessage({cmd: ok ? 'closeWindow' : 'closeCancelled'}))");
}

// Finder / Explorer / a second launch: switch to the tab if it's open anywhere, else open in the front window
fn open_paths(app: &AppHandle, paths: Vec<PathBuf>) {
    for p in paths.iter().map(|p| canon(p)) {
        let key = p.to_string_lossy().into_owned();
        let label = {
            let g = st(app);
            g.wins.iter().find(|(_, v)| v.paths.contains(&key)).map(|(l, _)| l.clone())
                .or_else(|| g.wins.keys().find(|l| app.get_webview_window(l).is_some_and(|w| w.is_focused().unwrap_or(false))).cloned())
                .or_else(|| g.wins.keys().last().cloned())
        };
        let w = label.and_then(|l| app.get_webview_window(&l)).unwrap_or_else(|| new_window(app, true));
        let _ = w.set_focus();
        open_file(&w, &p);
    }
}

// ---- session restore: one entry per window, each a list of its open files ----
fn session_file(app: &AppHandle) -> Option<PathBuf> {
    app.path().app_config_dir().ok().map(|d| d.join("session.json"))
}

fn save_session(app: &AppHandle) {
    let all: Vec<Vec<String>> = st(app).wins.values().map(|w| w.paths.clone()).filter(|p| !p.is_empty()).collect();
    if let Some(f) = session_file(app) {
        let _ = fs::create_dir_all(f.parent().unwrap());
        let _ = fs::write(f, json!(all).to_string());
    }
}

fn load_session(app: &AppHandle) -> Vec<Vec<String>> {
    let saved: Vec<Vec<String>> = session_file(app).and_then(|f| fs::read_to_string(f).ok())
        .and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
    saved.into_iter().map(|w| w.into_iter().filter(|p| Path::new(p).is_file()).collect::<Vec<_>>()).filter(|w| !w.is_empty()).collect()
}

// ---- file helpers (stateless apart from line-ending memory: every command carries the path it's about) ----

// Real on-disk path, so the page's "already open?" check works on case-insensitive Windows/macOS paths
fn canon(p: &Path) -> PathBuf {
    let c = fs::canonicalize(p).unwrap_or_else(|_| p.into());
    let s = c.to_string_lossy();
    // Windows canonical paths come back as \\?\C:\...; keep the plain form (UNC shares keep their prefix)
    match s.strip_prefix(r"\\?\") { Some(r) if r.as_bytes().get(1) == Some(&b':') => PathBuf::from(r), _ => c.clone() }
}

// The folder as a URL this webview may load, so relative images (assets/x.png) render: Tauri's asset protocol
fn asset_url(dir: &Path) -> String {
    let mut s = dir.to_string_lossy().into_owned();
    if !s.ends_with(std::path::MAIN_SEPARATOR) { s.push(std::path::MAIN_SEPARATOR) }
    let enc: String = s.bytes().map(|b| if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") }).collect();
    if cfg!(windows) { format!("http://asset.localhost/{enc}") } else { format!("asset://localhost/{enc}") }
}

fn info(p: &Path) -> Value {
    json!({"path": p.to_string_lossy(), "name": p.file_name().unwrap_or_default().to_string_lossy(), "base": asset_url(p.parent().unwrap_or(p))})
}

fn open_file(w: &WebviewWindow, p: &Path) {
    let p = canon(p);
    let name = p.file_name().unwrap_or_default().to_string_lossy().into_owned();
    let Some(text) = fs::read(&p).ok().and_then(|b| String::from_utf8(b).ok()) else {
        return alert(w, &format!("Couldn't read {name} as UTF-8 text."));
    };
    let (text, format) = decode(&text);
    st(w.app_handle()).formats.insert(p.to_string_lossy().into_owned(), format);
    allow(w.app_handle(), &p);
    let i = info(&p);
    load(w, json!([i["name"], text, i["base"], i["path"], false]));
}

// The page works in LF without a BOM; remember what the file had so saving doesn't rewrite every line.
fn decode(text: &str) -> (String, (bool, bool)) {
    let bom = text.starts_with('\u{feff}');
    let text = text.trim_start_matches('\u{feff}');
    (text.replace("\r\n", "\n"), (bom, text.contains("\r\n")))
}

fn encode(text: &str, (bom, crlf): (bool, bool)) -> String {
    let body = if crlf { text.replace("\r\n", "\n").replace('\n', "\r\n") } else { text.to_string() };
    if bom { format!("\u{feff}{body}") } else { body }
}

fn write(w: &WebviewWindow, text: &str, p: &Path) -> bool {
    let format = st(w.app_handle()).formats.get(&*p.to_string_lossy()).copied().unwrap_or_default();
    let out = encode(text, format);
    // write a sibling temp file, then swap it in: a failed write never leaves a half-written document
    let tmp = p.with_file_name(format!(".{}.markquill-tmp", p.file_name().unwrap_or_default().to_string_lossy()));
    match fs::write(&tmp, out).and_then(|_| fs::rename(&tmp, p)) {
        Ok(_) => true,
        Err(e) => { let _ = fs::remove_file(&tmp); alert(w, &e.to_string()); false }
    }
}

fn save_panel(w: &WebviewWindow, name: &str) -> Option<PathBuf> {
    w.dialog().file().set_parent(w).set_file_name(if name.is_empty() { "Untitled.md" } else { name })
        .blocking_save_file().and_then(|f| f.into_path().ok())
}

fn alert(w: &WebviewWindow, msg: &str) {
    w.dialog().message(msg).parent(w).show(|_| {}); // non-blocking: may be called on the main thread
}

// A link clicked in a document. Web and mail links go to the browser; a Markdown file opens in a tab;
// any other file is shown in its folder rather than run, so a link in a downloaded document can't launch a program.
fn open_link(w: &WebviewWindow, href: &str, doc: &str) {
    let lower = href.to_ascii_lowercase();
    if ["http://", "https://", "mailto:"].iter().any(|p| lower.starts_with(p)) {
        let _ = w.opener().open_url(href, None::<&str>);
        return;
    }
    if lower.contains(':') { return } // javascript:, file:, other schemes: never followed
    if doc.is_empty() { return alert(w, "Save this document first: links are relative to its folder.") }
    let rel = percent_decode(href.split(['#', '?']).next().unwrap_or(""));
    let p = Path::new(doc).parent().unwrap_or(Path::new(".")).join(&rel);
    if !p.exists() { return alert(w, &format!("{rel} doesn't exist.")) }
    let md = p.extension().and_then(|e| e.to_str()).is_some_and(|e| ["md", "markdown", "mdown", "txt"].contains(&e.to_ascii_lowercase().as_str()));
    if md && p.is_file() { open_file(w, &p) } else { let _ = w.opener().reveal_item_in_dir(&p); }
}

fn percent_decode(s: &str) -> String {
    let (b, mut out, mut i) = (s.as_bytes(), Vec::with_capacity(s.len()), 0);
    while i < b.len() {
        let hex = b.get(i + 1..i + 3).filter(|h| b[i] == b'%' && h.iter().all(u8::is_ascii_hexdigit));
        match hex {
            Some(h) => { out.push(u8::from_str_radix(std::str::from_utf8(h).unwrap(), 16).unwrap()); i += 3 }
            None => { out.push(b[i]); i += 1 }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn allow(app: &AppHandle, p: &Path) { st(app).files.insert(p.to_string_lossy().into_owned()); }
fn known(app: &AppHandle, p: &str) -> bool { st(app).files.contains(p) }

fn err(msg: impl Into<String>) -> Value { json!({"error": msg.into()}) }

// Names that are valid on every platform, so documents survive a trip to Windows
fn valid_name(name: &str) -> bool {
    let stem = name.split('.').next().unwrap_or("").to_ascii_uppercase();
    let reserved = matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || (stem.len() == 4 && (stem.starts_with("COM") || stem.starts_with("LPT")) && stem.as_bytes()[3].is_ascii_digit());
    !name.is_empty() && !name.starts_with('.') && !name.ends_with(['.', ' ']) && !reserved
        && !name.contains(['/', '\\', ':', '*', '?', '"', '<', '>', '|']) && !name.chars().any(char::is_control)
}

fn rename(app: &AppHandle, path: &str, name: &str) -> Value {
    if path.is_empty() { return err("This document hasn't been saved yet.") }
    if !valid_name(name) { return err("That isn't a valid file name.") }
    let src = PathBuf::from(path);
    let dst = src.with_file_name(name);
    // case-only renames (notes.md → Notes.md) hit the same file on macOS and Windows, so they're not a collision.
    // Linux is case-sensitive: there a Notes.md next to notes.md is a different file and must not be overwritten.
    let same = if cfg!(target_os = "linux") { dst == src } else { dst.to_string_lossy().to_lowercase() == path.to_lowercase() };
    if !same && dst.exists() { return err(format!("{name} already exists in this folder.")) }
    match fs::rename(&src, &dst) {
        Ok(_) => {
            let mut g = st(app);
            if let Some(f) = g.formats.remove(path) { g.formats.insert(dst.to_string_lossy().into_owned(), f); }
            g.files.remove(path);
            g.files.insert(dst.to_string_lossy().into_owned());
            info(&dst)
        }
        Err(e) => err(e.to_string()),
    }
}

// Attachments go into <doc folder>/assets/ (or images/), never overwriting; returns a relative link for the markdown.
fn save_asset(doc: &str, name: &str, b64: &str, folder: &str) -> Value {
    if doc.is_empty() { return err(format!("Save the document first: attachments are copied into its {folder} folder.")) }
    let Ok(data) = base64::engine::general_purpose::STANDARD.decode(b64) else { return err("Couldn't read that image.") };
    let dir = Path::new(doc).parent().unwrap_or(Path::new(".")).join(folder);
    let clean: String = name.chars().map(|c| if c.is_ascii_alphanumeric() || "._-".contains(c) { c } else { '-' }).collect();
    let (stem, ext) = match clean.rsplit_once('.') { Some((s, e)) if !s.is_empty() => (s.to_string(), e.to_string()), _ => (clean.clone(), String::new()) };
    let mut file = dir.join(&clean);
    let mut n = 1;
    while file.exists() {
        file = dir.join(format!("{stem}-{n}.{}", if ext.is_empty() { "png" } else { &ext }));
        n += 1;
    }
    match fs::create_dir_all(&dir).and_then(|_| fs::write(&file, data)) {
        Ok(_) => json!({"path": format!("{folder}/{}", file.file_name().unwrap().to_string_lossy())}),
        Err(e) => err(e.to_string()),
    }
}

fn main() {
    tauri::Builder::default()
        // must be first: a second launch (Explorer double-click, `markquill file.md`) hands its files to this one
        .plugin(tauri_plugin_single_instance::init(|app, argv, cwd| {
            let files: Vec<PathBuf> = argv.iter().skip(1).map(|a| Path::new(&cwd).join(a)).filter(|p| p.is_file()).collect();
            if files.is_empty() {
                if let Some(w) = app.webview_windows().values().next() { let _ = w.set_focus(); }
            } else { open_paths(app, files) }
        }))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(St::default())
        .invoke_handler(tauri::generate_handler![native])
        .on_page_load(|w, p| {
            if p.event() != PageLoadEvent::Finished { return }
            let queued = {
                let mut g = st(w.app_handle());
                let Some(win) = g.wins.get_mut(w.label()) else { return };
                win.ready = true;
                std::mem::take(&mut win.queued)
            };
            for args in queued { let _ = w.eval(&format!("load(...{args})")); }
        })
        .on_window_event(|win, ev| match ev {
            WindowEvent::CloseRequested { api, .. } => {
                let dirty = st(win.app_handle()).wins.get(win.label()).is_some_and(|w| w.dirty);
                if dirty {
                    api.prevent_close();
                    if let Some(w) = win.app_handle().get_webview_window(win.label()) { ask_close(&w) }
                }
            }
            WindowEvent::Destroyed => {
                let app = win.app_handle();
                let keep = {
                    let mut g = st(app);
                    g.wins.remove(win.label());
                    !g.quitting && !g.wins.is_empty()
                };
                if keep { save_session(app) } // closing the last window (or quitting) keeps its tabs for next launch
            }
            _ => {}
        })
        .setup(|app| {
            let h = app.handle();
            let files: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).filter(|p| p.is_file()).collect();
            let session = load_session(h);
            if !files.is_empty() {
                let w = new_window(h, false);
                files.iter().for_each(|f| open_file(&w, f));
            } else if session.is_empty() {
                new_window(h, false);
            } else {
                for (i, paths) in session.iter().enumerate() {
                    let w = new_window(h, i > 0);
                    paths.iter().for_each(|p| open_file(&w, Path::new(p)));
                }
            }
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("couldn't start MarkQuill")
        .run(|app, ev| match ev {
            RunEvent::ExitRequested { api, .. } => {
                let dirty: Vec<String> = {
                    let mut g = st(app);
                    g.quitting = true; // windows closing from here on are part of the quit: keep them in the session
                    g.wins.iter().filter(|(_, w)| w.dirty).map(|(l, _)| l.clone()).collect()
                };
                if !dirty.is_empty() {
                    api.prevent_exit();
                    dirty.iter().filter_map(|l| app.get_webview_window(l)).for_each(|w| ask_close(&w));
                }
            }
            #[cfg(target_os = "macos")]
            RunEvent::Opened { urls } => open_paths(app, urls.iter().filter_map(|u| u.to_file_path().ok()).collect()),
            _ => {}
        });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn line_endings_and_bom_survive_a_round_trip() {
        for original in ["\u{feff}# A\r\n\r\nb\r\n", "# A\n\nb\n", "\u{feff}plain\n", "# A\r\nb"] {
            let (page, format) = decode(original);
            assert!(!page.contains('\r') && !page.starts_with('\u{feff}'));
            assert_eq!(encode(&page, format), original);
        }
    }

    #[test]
    fn file_names_valid_everywhere() {
        for ok in ["notes.md", "Notes 2.md", "con-notes.md", "COM.md"] { assert!(valid_name(ok), "{ok}") }
        for bad in ["", ".hidden", "a/b.md", r"a\b.md", "a:b.md", "why?.md", "CON.md", "nul", "lpt1.txt", "trailing.", "x\u{7}.md"] {
            assert!(!valid_name(bad), "{bad}")
        }
    }

    #[test]
    fn links_decode_like_the_page_encoded_them() {
        assert_eq!(percent_decode("My%20Notes/a%2Bb.md"), "My Notes/a+b.md");
        assert_eq!(percent_decode("caf%C3%A9.md"), "café.md");
        assert_eq!(percent_decode("100%.md"), "100%.md"); // a lone % stays
        assert_eq!(percent_decode("x%zz%4"), "x%zz%4");
    }

    #[test]
    fn asset_urls_are_loadable() {
        // the folder gets the OS's own separator; Windows serves assets over http://asset.localhost
        let (dir, url) = if cfg!(windows) {
            (r"C:\Users\me\My Notes", "http://asset.localhost/C%3A%5CUsers%5Cme%5CMy%20Notes%5C")
        } else {
            ("/Users/me/My Notes", "asset://localhost/%2FUsers%2Fme%2FMy%20Notes%2F")
        };
        assert_eq!(asset_url(Path::new(dir)), url);
    }
}

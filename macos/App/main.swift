import Cocoa
import UniformTypeIdentifiers
import WebKit

// macOS host. The app itself (tabs, editor, settings) lives in web/index.html so it works the same on every
// platform; this file only answers the page's `native.postMessage({cmd, ...})` for what a web page can't do:
// files, native dialogs, clipboard, printing and windows. A Windows/Linux shell implements the same commands.

// One window = one page = its own set of tabs.
final class Doc: NSObject, NSWindowDelegate, WKScriptMessageHandlerWithReply, WKNavigationDelegate, WKUIDelegate {
    let window: NSWindow
    let web: WKWebView
    unowned let app: AppDelegate
    var ready = false
    var queued: [[Any]] = []   // load() calls waiting for the page
    var paths: [String] = []   // saved files open in this window's tabs (session restore)
    var dirty = false          // any tab has unsaved changes

    init(app: AppDelegate, fresh: Bool) {
        self.app = app
        let cfg = WKWebViewConfiguration()
        if fresh { // later windows start with an empty tab instead of the welcome page
            cfg.userContentController.addUserScript(WKUserScript(source: "window.FRESH = true", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        web = WKWebView(frame: .zero, configuration: cfg)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        cfg.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "native")
        web.navigationDelegate = self
        web.uiDelegate = self // without it WKWebView ignores <input type=file> (the attach button)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed // tabs are drawn by the page
        window.title = "MarkQuill"
        window.contentView = web
        window.delegate = self
        let dir = Bundle.main.resourceURL!.appendingPathComponent("web")
        // read access to / so images next to the open .md files (assets/…) can render
        web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        ready = true
        queued.forEach { call("load", $0) }
        queued = []
    }

    // backstop for link handling in the page: this window only ever shows the app itself
    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler done: @escaping (WKNavigationActionPolicy) -> Void) {
        done(a.request.url?.isFileURL == true || a.request.url?.scheme == "about" ? .allow : .cancel)
    }

    // the page's file picker (Attach image or file)
    func webView(_ w: WKWebView, runOpenPanelWith p: WKOpenPanelParameters, initiatedByFrame f: WKFrameInfo, completionHandler done: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = p.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { done($0 == .OK ? panel.urls : nil) }
    }

    func load(_ args: [Any]) { if ready { call("load", args) } else { queued.append(args) } }

    func openFile(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return alert("Couldn't read \(url.lastPathComponent) as UTF-8 text.")
        }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        load([url.lastPathComponent, text, baseDir(url), url.path, false])
    }

    // A link clicked in a document. Web and mail links go to the browser; a Markdown file opens in a tab;
    // any other file is shown in Finder rather than run, so a link in a downloaded document can't launch a program.
    func openLink(_ href: String, doc: String) {
        let lower = href.lowercased()
        if ["http://", "https://", "mailto:"].contains(where: lower.hasPrefix), let u = URL(string: href) { NSWorkspace.shared.open(u); return }
        if lower.contains(":") { return } // javascript:, file:, other schemes: never followed
        guard !doc.isEmpty else { return alert("Save this document first: links are relative to its folder.") }
        let raw = href.split(whereSeparator: { $0 == "#" || $0 == "?" }).first.map(String.init) ?? ""
        let rel = raw.removingPercentEncoding ?? raw
        let u = URL(fileURLWithPath: doc).deletingLastPathComponent().appendingPathComponent(rel).standardized
        guard FileManager.default.fileExists(atPath: u.path) else { return alert("\(rel) doesn't exist.") }
        if ["md", "markdown", "mdown", "txt"].contains(u.pathExtension.lowercased()) { openFile(u) }
        else { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }

    func call(_ fn: String, _ args: [Any]) {
        let json = String(data: try! JSONSerialization.data(withJSONObject: args), encoding: .utf8)!
        web.evaluateJavaScript("\(fn)(...\(json))")
    }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage, replyHandler reply: @escaping (Any?, String?) -> Void) {
        guard let b = m.body as? [String: Any], let cmd = b["cmd"] as? String else { return reply(nil, "bad message") }
        func s(_ k: String) -> String { b[k] as? String ?? "" }
        switch cmd {
        case "state":
            window.title = s("title").isEmpty ? "MarkQuill" : s("title")
            window.representedURL = s("path").isEmpty ? nil : URL(fileURLWithPath: s("path"))
            dirty = b["dirty"] as? Bool ?? false
            window.isDocumentEdited = dirty
            paths = b["paths"] as? [String] ?? []
            app.saveSession()
        case "open":
            let p = NSOpenPanel()
            p.allowsMultipleSelection = true
            p.allowedContentTypes = [UTType("net.daringfireball.markdown") ?? .plainText, .plainText]
            if p.runModal() == .OK { p.urls.forEach(openFile) }
        case "save": // path given: write it. No path: ask where, reply with the new identity.
            if !s("path").isEmpty { return reply(write(s("data"), to: URL(fileURLWithPath: s("path"))), nil) }
            if let u = savePanel(s("name")), write(s("data"), to: u) { return reply(info(u), nil) }
            return reply(false, nil)
        case "rename":
            return reply(rename(s("path"), to: s("name")), nil)
        case "asset":
            return reply(saveAsset(doc: s("doc"), name: s("name"), base64: s("data"), folder: s("folder") == "images" ? "images" : "assets"), nil)
        case "export":
            if let u = savePanel(s("name")) { write(s("data"), to: u) }
        case "copy":
            let pb = NSPasteboard.general
            pb.clearContents()
            if !s("html").isEmpty { pb.setString(s("html"), forType: .html) }
            pb.setString(s("text"), forType: .string)
        case "print":
            printDoc(paper: s("paper"), marginMM: Double(s("margin")) ?? 18, numbers: s("numbers") == "true")
        case "newWindow": // optionally carrying a tab moved out of this window
            let d = app.newDoc(fresh: true)
            if !s("name").isEmpty { d.load([s("name"), s("text"), s("base"), s("path"), b["dirty"] as? Bool ?? false]) }
        case "link":
            openLink(s("href"), doc: s("doc"))
        case "closeWindow": // the page closed its last tab; nothing is unsaved
            dirty = false
            window.close()
        default: break
        }
        reply(nil, nil)
    }

    func printDoc(paper: String, marginMM: Double, numbers: Bool) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = paper == "letter" ? NSSize(width: 612, height: 792) : NSSize(width: 595.28, height: 841.89)
        let m = marginMM * 72 / 25.4
        (info.topMargin, info.bottomMargin, info.leftMargin, info.rightMargin) = (m, m, m, m)
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = numbers // title + page numbers
        let op = web.printOperation(with: info)
        op.view?.frame = web.bounds // ponytail: without a frame WKWebView prints blank pages
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // ---- unsaved changes ----
    func confirmClose(_ done: @escaping (Bool) -> Void) {
        guard dirty else { return done(true) }
        window.makeKeyAndOrderFront(nil)
        let a = NSAlert()
        a.messageText = "Save changes before closing?"
        a.informativeText = "Some documents in this window have unsaved changes."
        a.addButton(withTitle: "Save All"); a.addButton(withTitle: "Cancel"); a.addButton(withTitle: "Don't Save")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            web.callAsyncJavaScript("return await saveAll()", arguments: [:], in: nil, in: .page) { r in
                if case .success(let v) = r, (v as? Bool) == true { done(true) } else { done(false) }
            }
        case .alertThirdButtonReturn: done(true)
        default: done(false)
        }
    }

    func windowShouldClose(_ s: NSWindow) -> Bool {
        if !dirty { return true }
        confirmClose { ok in if ok { self.dirty = false; self.window.close() } }
        return false
    }

    func windowWillClose(_ n: Notification) {
        web.configuration.userContentController.removeAllScriptMessageHandlers() // breaks the page ↔ Doc retain cycle
        app.remove(self)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var docs: [Doc] = []
    var pendingURLs: [URL] = []
    var launched = false
    var keyDoc: Doc? { docs.first { $0.window.isKeyWindow } ?? docs.first { $0.window.isMainWindow } ?? docs.last }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.mainMenu = makeMenu()
        // session restore: one entry per window, each a list of its open files
        let session = (UserDefaults.standard.array(forKey: "session") as? [[String]] ?? [])
            .map { $0.filter { FileManager.default.fileExists(atPath: $0) } }.filter { !$0.isEmpty }
        if !pendingURLs.isEmpty {
            let d = newDoc(fresh: false)
            pendingURLs.forEach(d.openFile)
        } else if session.isEmpty {
            newDoc(fresh: false)
        } else {
            for (i, paths) in session.enumerated() {
                let d = newDoc(fresh: i > 0)
                paths.forEach { d.openFile(URL(fileURLWithPath: $0)) }
            }
        }
        launched = true
        NSApp.activate(ignoringOtherApps: true)
    }

    // Finder double-click / "Open With": switch to the tab if it's open anywhere, else open in the front window
    func application(_ a: NSApplication, open urls: [URL]) {
        guard launched else { pendingURLs += urls; return }
        for u in urls {
            let d = docs.first { $0.paths.contains(u.path) } ?? keyDoc ?? newDoc(fresh: true)
            d.window.makeKeyAndOrderFront(nil)
            d.openFile(u)
        }
    }

    @discardableResult
    func newDoc(fresh: Bool) -> Doc {
        let d = Doc(app: self, fresh: fresh)
        if let last = docs.last { d.window.setFrame(last.window.frame.offsetBy(dx: 26, dy: -26), display: false) }
        else { d.window.center(); d.window.setFrameAutosaveName("main") }
        docs.append(d)
        d.window.makeKeyAndOrderFront(nil)
        return d
    }

    func remove(_ d: Doc) {
        docs.removeAll { $0 === d }
        if !docs.isEmpty { saveSession() } // closing the last window quits: keep its tabs for next launch
    }

    func saveSession() {
        UserDefaults.standard.set(docs.map(\.paths).filter { !$0.isEmpty }, forKey: "session")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        let dirty = docs.filter(\.dirty)
        if dirty.isEmpty { return .terminateNow }
        confirm(dirty[...])
        return .terminateLater
    }

    func confirm(_ list: ArraySlice<Doc>) {
        guard let d = list.first else { return NSApp.reply(toApplicationShouldTerminate: true) }
        d.confirmClose { ok in ok ? self.confirm(list.dropFirst()) : NSApp.reply(toApplicationShouldTerminate: false) }
    }

    @objc func newWindow(_ s: Any?) { newDoc(fresh: true) }
    @objc func newTab(_ s: Any?) { (keyDoc ?? newDoc(fresh: true)).web.evaluateJavaScript("newTab()") }
    @objc func renameTab(_ s: Any?) { keyDoc?.web.evaluateJavaScript("renameTab(T())") }

    // Edit menu is required: without it ⌘C/⌘V/⌘Z don't reach the web view.
    // ⌘T/⌘W/⌘O/⌘S are handled by the page, so those menu items carry no shortcut (no double handling).
    func makeMenu() -> NSMenu {
        let main = NSMenu()
        @discardableResult
        func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let m = NSMenu(title: title); items.forEach(m.addItem)
            let i = NSMenuItem(); i.submenu = m; main.addItem(i)
            return m
        }
        func item(_ t: String, _ a: Selector, _ k: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k); i.keyEquivalentModifierMask = mods; return i
        }
        sub("MarkQuill", [item("Hide MarkQuill", #selector(NSApplication.hide(_:)), "h"),
                       item("Quit MarkQuill", #selector(NSApplication.terminate(_:)), "q")])
        sub("File", [item("New Tab", #selector(newTab(_:))),
                     item("New Window", #selector(newWindow(_:)), "n"),
                     .separator(),
                     item("Rename…", #selector(renameTab(_:))),
                     .separator(),
                     item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift])])
        sub("Edit", [item("Undo", Selector(("undo:")), "z"),
                     item("Redo", Selector(("redo:")), "z", [.command, .shift]),
                     .separator(),
                     item("Cut", #selector(NSText.cut(_:)), "x"),
                     item("Copy", #selector(NSText.copy(_:)), "c"),
                     item("Paste", #selector(NSText.paste(_:)), "v"),
                     item("Paste as Plain Text", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
                     item("Select All", #selector(NSText.selectAll(_:)), "a")])
        NSApp.windowsMenu = sub("Window", [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
                                           item("Zoom", #selector(NSWindow.performZoom(_:))),
                                           .separator(),
                                           item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))])
        return main
    }
}

// ---- file helpers (stateless: every command carries the path it's about) ----
func baseDir(_ url: URL) -> String { url.deletingLastPathComponent().absoluteString }
func info(_ u: URL) -> [String: String] { ["path": u.path, "name": u.lastPathComponent, "base": baseDir(u)] }

func rename(_ path: String, to name: String) -> [String: String] {
    guard !path.isEmpty else { return ["error": "This document hasn't been saved yet."] }
    guard !name.isEmpty, !name.contains("/"), !name.contains(":"), !name.hasPrefix(".") else { return ["error": "That isn't a valid file name."] }
    let src = URL(fileURLWithPath: path)
    let dst = src.deletingLastPathComponent().appendingPathComponent(name)
    // case-only renames (notes.md → Notes.md) hit the same file on macOS, so they're not a collision
    if dst.path.lowercased() != src.path.lowercased(), FileManager.default.fileExists(atPath: dst.path) {
        return ["error": "\(name) already exists in this folder."]
    }
    do { try FileManager.default.moveItem(at: src, to: dst); return info(dst) }
    catch { return ["error": error.localizedDescription] }
}

// Images go into <doc folder>/assets/ (or images/), never overwriting; returns a relative link for the markdown.
func saveAsset(doc: String, name: String, base64: String, folder: String) -> [String: String] {
    guard !doc.isEmpty else { return ["error": "Save the document first: attachments are copied into its \(folder) folder."] }
    guard let data = Data(base64Encoded: base64) else { return ["error": "Couldn't read that image."] }
    let dir = URL(fileURLWithPath: doc).deletingLastPathComponent().appendingPathComponent(folder)
    let clean = name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
    let stem = (clean as NSString).deletingPathExtension, ext = (clean as NSString).pathExtension
    var url = dir.appendingPathComponent(clean), n = 1
    while FileManager.default.fileExists(atPath: url.path) {
        url = dir.appendingPathComponent("\(stem)-\(n).\(ext.isEmpty ? "png" : ext)"); n += 1
    }
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url)
        return ["path": "\(folder)/" + url.lastPathComponent]
    } catch { return ["error": error.localizedDescription] }
}

func savePanel(_ name: String) -> URL? {
    let p = NSSavePanel()
    p.nameFieldStringValue = name.isEmpty ? "Untitled.md" : name
    return p.runModal() == .OK ? p.url : nil
}

@discardableResult
func write(_ s: String, to u: URL) -> Bool {
    do { try s.write(to: u, atomically: true, encoding: .utf8); return true }
    catch { NSAlert(error: error).runModal(); return false }
}

func alert(_ msg: String) { let a = NSAlert(); a.messageText = msg; a.runModal() }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

# MarkQuill

**A small, fast Markdown viewer and editor for macOS, Windows and Linux.**

MarkQuill opens `.md` files in a clean reading view and lets you edit them inline like a document, or as raw Markdown, one shortcut apart. It uses your system's own web engine instead of bundling a browser, so it downloads in about **4 MB** and uses about as much memory as one browser tab.

| | Typical Electron editor | **MarkQuill** |
|---|---|---|
| Download | 80–150 MB | ~4 MB (macOS) |
| Engine | Bundled Chromium | The one your OS already has (WebKit, WebView2, WebKitGTK) |
| Works offline | Usually | Always: math, diagrams and code colors are bundled |

## Download

Get the latest installer from [Releases](https://github.com/sarat03/markquill/releases):

| OS | File |
|---|---|
| macOS (Apple silicon / Intel) | `MarkQuill_x.y.z_aarch64.dmg` / `MarkQuill_x.y.z_x64.dmg` |
| Windows 10/11 | `MarkQuill_x.y.z_x64-setup.exe` or `.msi` |
| Linux | `.deb` (Debian, Ubuntu, Mint…) or `.rpm` (Fedora, openSUSE…) |

The builds are not code-signed yet, so the first launch shows a warning:
- **macOS:** right-click MarkQuill in Applications → **Open** → **Open**. You only need to do this once.
- **Windows:** on the SmartScreen prompt, click **More info** → **Run anyway**.
- **Linux:** `sudo apt install ./MarkQuill_*.deb` or `sudo dnf install ./MarkQuill-*.rpm`. The package pulls in the system's WebKitGTK.

## Features

**Read, edit or write source, one shortcut apart**
- **View** (⌘1): read and copy; nothing can change by accident.
- **Edit** (⌘2): inline editing like a document. Type `/` on an empty line for the Quick Insert menu (headings, lists, tables, math, diagrams…).
- **Source** (⌘3): raw Markdown. Writing modes: Standard, Source, Typewriter (caret line stays centred) and Focus (dims everything but the current block).

**Blocks.** Click the badge in a block's margin (¶, H1…) to duplicate it, turn it into another kind or delete it. Drag the badge to move the block.

**Rendering** (all offline): CommonMark and GFM (tables, task lists, strikethrough, autolinks), footnotes, `[toc]`, `==highlight==`, `^sup^` / `~sub~`, YAML front matter, sanitized HTML, KaTeX math, and diagrams: Mermaid (flowchart, sequence, Gantt…), markmap mind maps and flowchart.js.

**Files and tabs**
- Tabs and windows: drag a tab to reorder it, or out of the window to move it to a new one. Your open files come back on the next launch.
- Double-click a tab to rename the file on disk.
- Paste, drop or attach images and files. They are copied into `./assets` (or `./images`) next to the document and never overwrite an existing file.
- Find & replace, with case-sensitive and regex options.
- Links: web links open in your browser, links to other Markdown files open in a tab, and links to other files show them in Finder or Explorer.
- Optional auto-save for files that are already on disk.
- Line endings and a BOM are kept on save, so a file from Windows stays a Windows file.

**Export and copy.** Export to HTML (self-contained), PDF (paper size, margins and page numbers) or Markdown. Copy as Markdown, rich text, HTML or plain text.

**Appearance.** Auto/light/dark theme; sans, serif or mono text; size, line height and page width; code font, size, tab width and colors (GitHub, VS Code, Red Accent); plus your own CSS. All changes apply live.

### Keyboard shortcuts

On Windows and Linux, use **Ctrl** for ⌘, **Alt** for ⌥ and **Shift** for ⇧. The app shows them that way too.

| Action | Keys | | Action | Keys |
|---|---|---|---|---|
| View / Edit / Source | ⌘1 / ⌘2 / ⌘3 | | Open… | ⌘O |
| Save | ⌘S | | Find & replace | ⌘F |
| New tab / close tab | ⌘T / ⌘W | | New window | ⌘N |
| Next / previous tab | Ctrl+Tab / Ctrl+⇧Tab | | Open documents sidebar | ⌘\ |
| Settings | ⌘, | | Paragraph / Heading 1–6 | ⌥⌘0 / ⌥⌘1–6 |
| Quote | ⌥⌘Q | | Ordered / bullet / task list | ⌥⇧⌘O / U / X |
| Duplicate block | ⇧⌘P | | New paragraph / delete block | ⇧⌘N / ⇧⌘D |

## How it's built

The whole app (UI, editing, settings, export) is **one web page**, `web/index.html`, built on the bundled [Vditor](https://github.com/Vanessa219/vditor) editor. A thin native shell hosts it and does only what a web page can't: file dialogs, reading and writing files, the clipboard, printing and windows.

```
web/                 The app: index.html (plain HTML/CSS/JS, no framework, no bundler)
  vditor/            Bundled editor engine: rendering, math, diagrams, code colors
src-tauri/           Cross-platform shell (Rust + Tauri 2) for macOS, Windows and Linux
  src/main.rs        The native commands, session restore, file handling
  tauri.conf.json    App name, identifier, file associations, bundling
package.json         Tauri CLI scripts: dev, build, icon
macos/               Mac-only extras (Swift)
  App/               The original native macOS shell (Cocoa + WKWebView)
  QuickLook/         Quick Look extension: spacebar in Finder renders with the same page
  build.sh           Builds build/MarkQuill.app with Quick Look embedded
.github/workflows/   CI: tests, builds and a launch check on every OS; draft release on tags
```

The page talks to its shell with `native.postMessage({cmd, ...})` and gets a promise back. There are ten commands: `state`, `open`, `save`, `rename`, `asset`, `export`, `copy`, `print`, `newWindow` and `closeWindow`. A new shell only needs to answer these; the page doesn't change.

## Build from source

### Cross-platform app (Tauri)

Needs [Rust](https://rustup.rs) and Node.js 18+. On Linux, also the WebKitGTK dev packages:

```bash
sudo apt install libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev libxdo-dev libssl-dev
```

Then:

```bash
npm install
npm run dev
```

`npm run dev` runs the app. `npm run build` creates installers in `src-tauri/target/release/bundle/`. `cargo test` in `src-tauri/` runs the unit tests. To replace the placeholder icon, run `npm run icon path/to/icon.png`.

### macOS app with Quick Look (Swift)

Needs the Xcode command line tools:

```bash
macos/build.sh
open build/MarkQuill.app
```

This builds `build/MarkQuill.app` with the Quick Look extension embedded. After that, pressing spacebar on a `.md` file in Finder renders it with the same page the app uses. The Tauri build doesn't include Quick Look yet.

### Working on the UI

Edit `web/index.html` and reload. Every shell loads the same file, so a UI change reaches every platform.

## Releasing

1. Set the new version in `src-tauri/Cargo.toml` (`version = "0.2.0"`). It's the only place the version lives, and the installers are named after it.
2. Merge that change to `main`, then tag it and push the tag:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. CI checks that the tag matches the version, builds every platform and attaches the installers to a draft release. Check the draft and publish it.

## Contributing

Bug reports, fixes and improvements are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers setup, where things live and what a pull request needs.

## Security

Please report security problems privately, not in a public issue. [SECURITY.md](SECURITY.md) explains how, and what MarkQuill does with your files and the network. In short: no telemetry, no network requests of its own, and HTML in documents is sanitized.

## License

MarkQuill is free software, licensed under the [GNU General Public License v3.0](LICENSE). You may use, study, share and modify it; if you distribute a modified version, it must also be under the GPL-3.0 with its source available.

Copyright © 2026 Sarat.

Bundled third-party components keep their own licenses. These include the [Vditor](https://github.com/Vanessa219/vditor) editor (MIT, © B3log) in `web/vditor/`, along with the math, diagram and code-color libraries it ships.

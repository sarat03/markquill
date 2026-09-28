# MarkQuill

**A small, fast Markdown viewer and editor for macOS, Windows and Linux.**

MarkQuill opens `.md` files in a clean reading view and lets you edit them inline like a document, or as raw Markdown, one shortcut apart. It uses your system's own web engine instead of bundling a browser, so the download is only about **5 MB** on Windows and Linux and **11 MB** on macOS (Quick Look included).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
  <img alt="MarkQuill showing a Markdown document with a task list, a table, highlighted code, math and a diagram" src="docs/screenshot-light.png">
</picture>

| | Typical Electron editor | **MarkQuill** |
|---|---|---|
| Download | Usually 80 MB or more | 5–11 MB |
| Engine | Bundled Chromium | The one your OS already has (WebKit, WebView2, WebKitGTK) |
| Works offline | Usually | Always: math, diagrams and code colors are bundled |
| Quick Look (macOS) | Rarely | Press Space on a `.md` file in Finder to see it rendered |

## Download

**macOS** ([Homebrew](https://brew.sh)):

```bash
brew tap sarat03/markquill https://github.com/sarat03/markquill
```

```bash
brew install --cask markquill
```

**Windows** (winget, coming soon: the package is waiting for approval):

```bash
winget install Sarat.MarkQuill
```

**Linux**, Debian, Ubuntu or Mint:

```bash
curl -fL "$(curl -s https://api.github.com/repos/sarat03/markquill/releases/latest | grep -o 'https://[^"]*amd64\.deb')" -o /tmp/markquill.deb && sudo apt install /tmp/markquill.deb
```

**Linux**, Fedora:

```bash
sudo dnf install "$(curl -s https://api.github.com/repos/sarat03/markquill/releases/latest | grep -o 'https://[^"]*x86_64\.rpm')"
```

Or get the installer from [Releases](https://github.com/sarat03/markquill/releases):

| OS | File |
|---|---|
| macOS, Apple silicon (M1 and later) | `MarkQuill_x.y.z_mac-m-arm.dmg` |
| macOS, Intel | `MarkQuill_x.y.z_mac-intel-x64.dmg` |
| Windows 10/11, x64 | `MarkQuill_x.y.z_win-x64-setup.exe` or `MarkQuill_x.y.z_win-x64.msi` |
| Windows 11, ARM | `MarkQuill_x.y.z_win-arm-setup.exe` |
| Linux: Debian 12+, Ubuntu 22.04+, Mint 21+ | `MarkQuill_x.y.z_linux-amd64.deb` |
| Linux: Fedora | `MarkQuill_x.y.z_linux-x86_64.rpm` |

The builds are not code-signed yet, so the first launch shows a warning:
- **macOS:** open MarkQuill once; macOS blocks it. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only need to do this once. If macOS says the app "is damaged", run `xattr -dr com.apple.quarantine /Applications/MarkQuill.app` in Terminal, then open it again.
- **Windows:** on the SmartScreen prompt, click **More info** → **Run anyway**.
- **Linux:** install with `sudo apt install ./MarkQuill_*.deb` or `sudo dnf install ./MarkQuill-*.rpm`. The package pulls in the system's WebKitGTK.

## Features

**Quick Look on macOS.** Select a Markdown file in Finder and press Space: it renders with the same page as View mode (math, diagrams, highlighted code), without opening the app. It comes with the app; open MarkQuill once after installing so macOS picks it up.

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

**Export and copy.** Export to HTML (self-contained), PDF or Markdown. PDF export shows the pages as they'll print: pick the paper size (A4, Letter, Legal, A3, A5), orientation, margins, font size, line height, a header and page numbers. The PDF is saved directly, always in light colors. Copy as Markdown, rich text, HTML or plain text.

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

The block shortcuts (headings, quote, lists, duplicate, new paragraph, delete) work in Edit mode.

## How it's built

The whole app (UI, editing, settings, export) is **one web page**, `web/index.html`, built on the bundled [Vditor](https://github.com/Vanessa219/vditor) editor. A thin native shell hosts it and does only what a web page can't: file dialogs, reading and writing files, the clipboard, printing and windows.

```
web/                 The app: index.html (plain HTML/CSS/JS, no framework, no bundler)
  vditor/            Bundled editor engine: rendering, math, diagrams, code colors
src-tauri/           Cross-platform shell (Rust + Tauri 2) for macOS, Windows and Linux
  src/main.rs        The native commands, session restore, file handling
  tauri.conf.json    App name, identifier, file associations, bundling, updater
  tauri.macos.conf.json  macOS only: bundles the Quick Look extension, ad-hoc signs the app
  icons/source/      App icon: SVG sources and build-icons.sh (light and dark on macOS)
package.json         Tauri CLI scripts: dev, build
macos/               Mac-only extras (Swift)
  App/               The original native macOS shell (Cocoa + WKWebView)
  QuickLook/         Quick Look extension: spacebar in Finder renders with the same page
  build-ql.sh        Builds the Quick Look extension (used by the Tauri build and build.sh)
  build.sh           Builds build/MarkQuill.app with Quick Look embedded
.github/workflows/   CI: tests, build and launch check (Linux per pull request, every OS per release)
```

The page talks to its shell with `native.postMessage({cmd, ...})` and gets a promise back. There are eleven commands: `state`, `open`, `save`, `rename`, `asset`, `export`, `copy`, `print`, `link`, `newWindow` and `closeWindow`. A new shell only needs to answer these; the page doesn't change. The Tauri shell also answers `version`, `fetchUpdate` and `installUpdate` for in-app updates, and `pdf`, which writes the page boxes straight to a PDF file; the page only uses them when it runs in Tauri.

## Build from source

### Cross-platform app (Tauri)

Needs [Rust](https://rustup.rs) and Node.js 18+. On Linux, also the WebKitGTK dev packages:

```bash
sudo apt install build-essential file libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev libxdo-dev libssl-dev
```

Then:

```bash
npm install
npm run dev
```

`npm run dev` runs the app. `npm run build` creates installers in `src-tauri/target/release/bundle/`. `cargo test` in `src-tauri/` runs the unit tests. The app icon is drawn in `src-tauri/icons/source/` (SVG); after editing it, run `src-tauri/icons/source/build-icons.sh` on a Mac with Xcode to rebuild every icon file.

### macOS app with Quick Look (Swift)

Needs the Xcode command line tools:

```bash
macos/build.sh
open build/MarkQuill.app
```

This builds `build/MarkQuill.app` with the Quick Look extension embedded. After that, pressing spacebar on a `.md` file in Finder renders it with the same page the app uses. The Tauri build (`npm run build` on a Mac) embeds the same extension.

### Working on the UI

Edit `web/index.html` while `npm run dev` is running, then reload the window (right-click → **Reload**). Every shell loads the same file, so a UI change reaches every platform.

## Contributing

Bug reports, fixes and improvements are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers setup, where things live and what a pull request needs.

## Security

Please report security problems privately, not in a public issue. [SECURITY.md](SECURITY.md) explains how, and what MarkQuill does with your files and the network. In short: no telemetry, no network requests of its own, and HTML in documents is sanitized.

## License

MarkQuill is free software, licensed under the [GNU General Public License v3.0](LICENSE). You may use, study, share and modify it. If you distribute it, modified or not, you must do so under the GPL-3.0 and make the source code available.

Copyright © 2026 Sarat.

Bundled third-party components keep their own licenses. These include the [Vditor](https://github.com/Vanessa219/vditor) editor (MIT, © B3log) in `web/vditor/`, along with the math, diagram and code-color libraries it ships.

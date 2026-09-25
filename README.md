# MDView

**A Markdown viewer/editor for macOS where the entire app is one HTML file.**

No Electron. No bundler. No build step for the UI. `web/index.html` — under 600 lines — *is* the app: tabs, three editing modes, themes, diagrams, math, exports, everything. The native side is ~340 lines of Swift whose only job is answering the things a browser sandbox can't do (open/save dialogs, printing, the window). The same HTML file also powers Quick Look, so pressing spacebar on a `.md` file in Finder renders it with the *exact* renderer the full app uses — not a second, worse one.

```
open README.md → spacebar in Finder → identical rendering to the full app
```

---

## Why this is different from every other Markdown app

| | Typora / Obsidian / Mark Text | VS Code + preview | Finder Quick Look (default) | **MDView** |
|---|---|---|---|---|
| Runtime | Electron/Chromium (~150–300 MB) | Electron | Native, but a *different*, plainer renderer than any editor | Native Cocoa + one system `WKWebView` |
| Quick Look (spacebar) preview | Not supported, or a separate bolted-on extension with its own styling | Not supported | Basic, unstyled, no diagrams/math | **Same renderer, same theme, same fidelity as the full app** |
| Editing modes | Usually one editing mode | Split-pane preview | View only | **View / Edit (inline WYSIWYG) / Source, live, one shortcut apart** |
| Diagrams & math | Varies, often plugin-dependent | Plugin-dependent | None | Mermaid, KaTeX, Graphviz, flowchart.js, ECharts, ABC notation, WaveDrom, markmap — bundled, work offline |
| Editing the app itself | Requires the vendor's build system | N/A | N/A | Edit `web/index.html` in any text editor and reload — it's plain HTML/CSS/JS |
| Cross-platform story | Ships one binary per OS, separate codebases in practice | Cross-platform by nature (general IDE) | macOS-only, fixed | **One web core designed to be reused by a Windows/Linux shell later — see `App/main.swift`** |
| Sandbox footprint | Varies | Large, general-purpose editor | N/A | App Sandbox, read-only file access, no network beyond `localhost` |

The core idea: **native chrome, web content, one source of truth.** Most apps either go full-native (fast, but you re-render Markdown yourself and Quick Look support is an afterthought) or go full-Electron (consistent everywhere, but heavy). MDView instead keeps a *thin* native shell — window, menu, file I/O, print — and puts 100% of the actual product (rendering, editing, settings, diagrams) in a single portable web page that both the main app **and** the Quick Look extension load verbatim.

## Features

**Three modes, one keystroke apart**
- **View** (⌘1) — read-only, select and copy freely, nothing can change
- **Edit** (⌘2) — inline WYSIWYG editing (Typora-style); type `/` for a block-insert menu, `:` for emoji
- **Source** (⌘3) — raw Markdown text

**Rich rendering**, all bundled locally (works fully offline, including in Quick Look):
CommonMark + GFM tables/tasks/strikethrough, footnotes, `[toc]`, `==mark==`, `^sup^`/`~sub~`, KaTeX math, YAML front matter, sanitized raw HTML, and fenced-block diagrams — Mermaid (flowchart/sequence/gantt/…), flowchart.js, Graphviz, ECharts, ABC music notation, WaveDrom, markmap.

**Everything else you'd expect from a real editor:**
- Multi-tab, multi-window — drag a tab out to spin off a new window, session restored on relaunch
- Files sidebar for browsing a project folder, `⌘\`
- Find & replace with regex, per-document
- Pasted/dropped images auto-saved next to the document (`./assets` or `./images`, never overwritten)
- Focus mode (dims everything but the current block) and typewriter mode (keeps the caret line centered)
- Live-editable appearance: theme (light/dark/Material/One Dark or follow system), font, font size, line height, page width, code font/size, tab width, and raw custom CSS — all apply instantly, no restart
- Configurable auto-save
- Export to HTML (self-contained, styles inlined), PDF (native print, page size/margins/page numbers), or Markdown; copy as Markdown/HTML/plain/rich text
- Word/character/paragraph counter

## How it's built

```
App/main.swift               macOS host: WKWebView + native.postMessage bridge (files, dialogs, print, windows)
QL/PreviewViewController.swift  Quick Look extension — loads the same web/index.html, header hidden
web/index.html                The entire app: UI, state, modes, settings, export — one file
web/vditor/                   Bundled editor engine (WYSIWYG/source rendering, diagrams, math)
build.sh                      Builds build/MDView.app (app + embedded Quick Look .appex), ad-hoc signed
```

The native layer never touches Markdown, rendering, or app state — it only relays a small command set (`open`, `save`, `asset`, `print`, `tree`, `copy`, `rename`, `newWindow`, …) over `window.webkit.messageHandlers.native`. Anything a browser *can* do (which is nearly everything here) lives entirely in `web/index.html`.

## Build & run

Requires the Xcode command line tools (macOS 13+).

```bash
./build.sh
open build/MDView.app
```

This produces `build/MDView.app` with the Quick Look extension (`MDPreview.appex`) embedded and registered — spacebar-preview any `.md` file in Finder afterward to see it in action.

## License

Application code is unlicensed pending a LICENSE file from the maintainer. The bundled [Vditor](https://github.com/Vanessa219/vditor) editor (`web/vditor/`) is MIT-licensed, © B3log.

# Contributing to MarkQuill

Thanks for helping. Bug reports, fixes and small improvements are all welcome.

## Reporting bugs and ideas

Open an [issue](https://github.com/sarat03/markquill/issues) with your OS, the MarkQuill version, what you did, and what happened instead. A small `.md` file that shows the problem helps a lot. For security problems, see [SECURITY.md](SECURITY.md) instead.

## Setting up

You need [Rust](https://rustup.rs) and Node.js 18+. On Linux you also need the WebKitGTK packages listed in the [README](README.md#build-from-source).

```bash
npm install
npm run dev
```

## Where things live

- **`web/index.html`** is the whole app: UI, editing, settings and export. Most changes happen here, in plain HTML, CSS and JavaScript. There's no framework and no build step.
- **`src-tauri/src/main.rs`** is the native shell. It only answers the page's `native.postMessage({cmd, ...})` calls: dialogs, files, clipboard, printing and windows.
- **`macos/`** is the original Swift app and its Quick Look extension. They're Mac-only and not part of the releases.

Keep that split. If a web page can do something, it belongs in `web/index.html`. Add a native command only when it can't, and keep the page working for every shell, including the Swift app.

## Before you open a pull request

- Keep changes focused: one fix or feature per pull request.
- Don't change the version number; releases are made by the maintainer.
- Match the surrounding code style. The code is compact and comments explain *why*, not *what*.
- Don't add a dependency for something a few lines can do. MarkQuill stays small on purpose: the download is about 4–5 MB.
- If you change the Rust code, run `cargo test` in `src-tauri/`, and add a test for any new logic.
- Test on the OS you have. CI builds, tests and launches the app on macOS, Windows and Linux for every pull request, so check that it's green.
- Keyboard shortcuts are written Mac-style (`⌘`, `⌥`, `⇧`) in the page. They become Ctrl, Alt and Shift on Windows and Linux automatically.

## License

MarkQuill is licensed under the [GNU GPL v3.0](LICENSE). By contributing, you agree that your contribution is licensed under the same terms.

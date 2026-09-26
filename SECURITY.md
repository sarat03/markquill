# Security

## Supported versions

Only the latest release gets security fixes. Update from [Releases](https://github.com/sarat03/markquill/releases).

## Reporting a vulnerability

Please **don't open a public issue** for a security problem. Report it privately through [GitHub security advisories](https://github.com/sarat03/markquill/security/advisories/new) instead. Include:

- what an attacker can do, and what they need (for example, "the victim opens this .md file");
- steps or a sample file that reproduce it;
- the MarkQuill version and your OS.

Reports are answered as soon as possible. Once a fix is released, the advisory is published with credit to you, unless you'd rather stay anonymous.

## What MarkQuill does and doesn't do

These points describe the Tauri app, which is what the Releases page ships.

- **No telemetry, no accounts, no update checks.** The app itself makes no network requests. Its editor, math, diagram and code-color engines are bundled.
- **Documents can load remote content.** An image or link in a Markdown file that points to a web address is fetched from there, the same as in any Markdown viewer.
- **Documents can't run code.** HTML in a document is sanitized before it's shown. Diagrams run in Mermaid's strict mode. Script links, event handlers and embedded frames are also stripped from whatever the diagram engines draw.
- **Links leave the app.** Clicking a web or email link opens your browser. A link to a Markdown file opens it in a tab. A link to any other file shows it in Finder or Explorer; MarkQuill never runs it. The app window can't be navigated to another page.
- **Files are only touched when you act.** MarkQuill reads files you open, and writes files you save, rename or attach to. The app only writes to files you opened or picked in a dialog, so even a document that got past the protections above couldn't overwrite anything else. It also stores its session (which files were open) in the app's data folder.
- **Installers are not code-signed yet.** macOS and Windows warn about this on first launch. Only download MarkQuill from this repository's Releases page.

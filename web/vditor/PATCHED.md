# Local changes to Vditor

`dist/` is Vditor's published build with these edits. Re-apply them after updating Vditor.

- **Mermaid runs in `strict` mode** (`securityLevel:"loose"` → `securityLevel:"strict"` in `dist/index.min.js` and
  `dist/method.min.js`). Vditor hard-codes `loose`, which lets a diagram in a document run script through
  `click … href "javascript:…"` and HTML labels.
- Unused parts are removed to keep the app small: highlight.js styles other than github, github-dark and vs2015;
  KaTeX `.woff`/`.ttf` fonts (woff2 kept); the graphviz, echarts, abcjs, smiles-drawer, wavedrom and plantuml engines.

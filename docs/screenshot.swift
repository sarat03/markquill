// Regenerates docs/screenshot-{light,dark}.png from docs/screenshot.md with the real page (macOS, WebKit):
//   swiftc -O docs/screenshot.swift -o /tmp/shot && for t in light dark; do /tmp/shot . docs/screenshot.md $t docs/screenshot-$t.png; done
import AppKit
import WebKit

let a = CommandLine.arguments
let repo = URL(fileURLWithPath: a[1]), doc = try! String(contentsOfFile: a[2], encoding: .utf8), theme = a[3], out = a[4]
let W: CGFloat = 1080, H: CGFloat = 720, bar: CGFloat = 28, margin: CGFloat = 48
let dark = theme == "dark"

final class Shot: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: W, height: H - bar))
    let window = NSWindow(contentRect: NSRect(x: -5000, y: 0, width: W, height: H - bar), styleMask: .borderless, backing: .buffered, defer: false)
    func start() {
        window.contentView = web
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.orderBack(nil)
        web.navigationDelegate = self
        web.loadFileURL(repo.appendingPathComponent("web/index.html"), allowingReadAccessTo: repo)
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        let js = """
        store.set('set-theme', '\(theme)'); document.documentElement.dataset.theme = themeName();
        load('Trip planning.md', \(String(data: try! JSONSerialization.data(withJSONObject: [doc], options: .fragmentsAllowed), encoding: .utf8)!)[0]);
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            w.evaluateJavaScript(js) { _, e in
                if let e { print("js error:", e) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.snap() } // let math, code colors and the diagram render
            }
        }
    }
    func snap() {
        web.takeSnapshot(with: nil) { img, err in
            guard let img else { print("snapshot failed:", err as Any); exit(1) }
            let scale: CGFloat = 2, cw = W + margin * 2, ch = H + margin * 2
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cw * scale), pixelsHigh: Int(ch * scale), bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = NSSize(width: cw, height: ch)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current!.imageInterpolation = .high
            let frame = NSRect(x: margin, y: margin, width: W, height: H)
            let shape = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
            // window shadow
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow(); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -10)
            sh.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.6 : 0.28); sh.set()
            NSColor.windowBackgroundColor.setFill(); shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            shape.addClip()
            // title bar with traffic lights and the document name
            NSColor(white: dark ? 0.17 : 0.93, alpha: 1).setFill()
            NSRect(x: margin, y: margin + H - bar, width: W, height: bar).fill()
            for (i, c) in [NSColor(red: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(red: 1, green: 0.74, blue: 0.18, alpha: 1),
                           NSColor(red: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
                c.setFill(); NSBezierPath(ovalIn: NSRect(x: margin + 14 + CGFloat(i) * 20, y: margin + H - bar + 8, width: 12, height: 12)).fill()
            }
            let title = NSAttributedString(string: "Trip planning.md", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                                                    .foregroundColor: NSColor(white: dark ? 0.85 : 0.25, alpha: 1)])
            title.draw(at: NSPoint(x: margin + (W - title.size().width) / 2, y: margin + H - bar + (bar - title.size().height) / 2))
            img.draw(in: NSRect(x: margin, y: margin, width: W, height: H - bar))
            // hairline border
            NSColor(white: dark ? 1 : 0, alpha: dark ? 0.15 : 0.12).setStroke(); shape.lineWidth = 1; shape.stroke()
            NSGraphicsContext.restoreGraphicsState()
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
            print("wrote", out); exit(0)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let s = Shot(); s.start()
app.run()

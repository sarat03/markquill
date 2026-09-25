import Cocoa
import Quartz
import WebKit

// Quick Look (spacebar in Finder): same renderer as the app, header hidden.
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    // loadFileURL rejects query strings, so flag Quick Look mode with a script injected before the page runs.
    let web: WKWebView = {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addUserScript(WKUserScript(source: "window.QL_MODE = true", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        return WKWebView(frame: .zero, configuration: cfg)
    }()
    var text = ""
    var name = ""
    var done: ((Error?) -> Void)?

    override func loadView() {
        web.navigationDelegate = self
        view = web
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do { text = try String(contentsOf: url, encoding: .utf8) } catch { return handler(error) }
        name = url.lastPathComponent
        done = handler
        let dir = Bundle.main.resourceURL!.appendingPathComponent("web")
        web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
    }

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        let json = String(data: try! JSONSerialization.data(withJSONObject: [name, text]), encoding: .utf8)!
        w.evaluateJavaScript("load(...\(json))") { _, err in self.finish(err) }
    }

    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { finish(e) }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { finish(e) }

    func finish(_ e: Error?) { done?(e); done = nil }
}

import AppKit
import WebKit

/// A general-purpose HTTPS viewer. Website behavior stays in the loaded page.
@MainActor
final class WebPageBrowser: NSWindowController, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let homeURL: URL
    private let pageTitle: String
    let webView: WKWebView
    private let status = NSTextField(labelWithString: "페이지를 여는 중…")
    private var children: [WebPageBrowser] = []
    private var resizeTimer: Timer?
    private let onResize: ((NSSize) -> Void)?

    init(url: URL, title: String, configuration: WKWebViewConfiguration? = nil,
         preferredContentSize: NSSize? = nil, onResize: ((NSSize) -> Void)? = nil) {
        homeURL = url
        pageTitle = title
        self.onResize = onResize
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil { config.websiteDataStore = .default() }
        webView = WKWebView(frame: .zero, configuration: config)
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let requested = preferredContentSize ?? NSSize(width: 1060, height: 780)
        let size = NSSize(width: min(visible.width, max(700, requested.width)),
                          height: min(max(500, visible.height - 40), max(500, requested.height)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "awtoday · \(title)"
        window.minSize = NSSize(width: 700, height: 500)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let back = NSButton(title: "뒤로", target: self, action: #selector(goBack))
        let home = NSButton(title: "처음", target: self, action: #selector(goHome))
        let reload = NSButton(title: "새로고침", target: self, action: #selector(refresh))
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let toolbar = NSStackView(views: [back, home, reload, status])
        toolbar.spacing = 8
        toolbar.orientation = .horizontal
        let content = NSView()
        window.contentView = content
        [toolbar, webView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 9),
            toolbar.heightAnchor.constraint(equalToConstant: 30),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 9),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func open() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if webView.url == nil { goHome() }
    }
    @objc private func goBack() { webView.goBack() }
    @objc private func goHome() { webView.load(URLRequest(url: homeURL)) }
    @objc private func refresh() { webView.reload() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        status.stringValue = webView.url?.host ?? "페이지 열림"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let error = error as NSError
        if error.code != NSURLErrorCancelled { status.stringValue = "페이지 연결 실패 (\(error.domain) \(error.code))" }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let scheme = navigationAction.request.url?.scheme?.lowercased(), ["https", "about"].contains(scheme) else {
            status.stringValue = "이 링크는 내장 브라우저에서 열 수 없습니다."
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let child = WebPageBrowser(url: homeURL, title: pageTitle, configuration: configuration)
        children.append(child)
        child.showWindow(nil)
        return child.webView
    }
    func webViewDidClose(_ webView: WKWebView) { close() }
    func windowDidResize(_ notification: Notification) {
        guard onResize != nil else { return }
        resizeTimer?.invalidate()
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.saveWindowSize() }
        }
    }
    func saveWindowSize() {
        resizeTimer?.invalidate()
        resizeTimer = nil
        if let size = window?.contentView?.frame.size { onResize?(size) }
    }
    func windowWillClose(_ notification: Notification) {
        saveWindowSize()
        children.forEach { $0.close() }
        children.removeAll()
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let window else { completionHandler(); return }
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "페이지 알림"
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let window else { completionHandler(false); return }
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "페이지 확인"
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
}

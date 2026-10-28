import AppKit
import SwiftUI

@main
struct AwTodayMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var browser: WebPageBrowser?
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenu()
        let model = AppModel()
        self.model = model
        let hosting = NSHostingView(rootView: MainView(model: model))
        // NSHostingView must not resize/recenter the window when details appear.
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "awtoday"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        self.window = window
        model.resizeAction = { [weak window, weak model] expanded in
            guard let window else { return }
            let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
            let frame = PopupLayout.frame(from: window.frame, chromeHeight: chrome,
                                          screen: window.screen?.visibleFrame, expanded: expanded)
            model?.detailHeight = max(0, frame.height - chrome - PopupLayout.baseHeight - PopupLayout.dividerHeight)
            window.setFrame(frame, display: true, animate: false)
        }
        model.closeAction = { [weak window] in window?.close() }
        model.browserAction = { [weak self] in
            guard let self else { return }
            guard let profile = self.model?.settings.webPage, let url = profile.validatedURL else {
                self.model?.editingWebPage = true
                return
            }
            if self.browser?.window?.isVisible != true || self.browser?.homeURL != url {
                self.browser?.close()
                self.browser = WebPageBrowser(url: url, title: profile.title,
                    preferredContentSize: profile.windowSize.map { NSSize(width: $0.width, height: $0.height) },
                    onResize: { [weak model] in model?.rememberWebPageWindowSize($0, address: profile.url) })
            }
            self.browser?.open()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.refresh()
    }
    func applicationDidBecomeActive(_ notification: Notification) { model?.onActivate() }
    func applicationWillTerminate(_ notification: Notification) { browser?.saveWindowSize() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        return true
    }
    private func setUpMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "awtoday 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}

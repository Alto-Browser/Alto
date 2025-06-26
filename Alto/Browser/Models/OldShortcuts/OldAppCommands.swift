import OpenADK
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandMenu("Archive") {
            archiveButton("Go Back", shortcut: Shortcuts.goBack) { tab in
                if let webview = tab.content[0] as? ADKWebPage {
                    if webview.canGoBack {
                        webview.webView.goBack()
                    }
                }
            }

            archiveButton("Go Forward", shortcut: Shortcuts.goForward) { tab in
                if let webview = tab.content[0] as? ADKWebPage {
                    if webview.canGoForward {
                        webview.webView.goForward()
                    }
                }
            }

            Divider()

            Button("Close Tab") {
                AltoWindowManager.shared.activeWindow?.state.tabManager.currentTab?.closeTab()
            }
            //            .keyboardShortcut(Shortcuts.closeTab)
        }

        CommandMenu("Tabs") {
            Button("New Tab") {
                AltoWindowManager.shared.activeWindow?.state.tabManager.createNewTab(location: "unpinned")
            }
            .keyboardShortcut(Shortcuts.newTab)
        }
    }

    private func archiveButton(
        _ title: String,
        shortcut: KeyboardShortcut,
        action: @escaping (ADKTab) -> ()
    ) -> some View {
        Button(title) {
            if let tab = AltoWindowManager.shared.activeWindow?.state.tabManager.currentTab {
                action(tab)
            }
        }
        .keyboardShortcut(shortcut)
    }
}

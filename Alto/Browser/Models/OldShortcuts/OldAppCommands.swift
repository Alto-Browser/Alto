import SwiftUI

/*
 struct AppCommands: Commands {
     var body: some Commands {
         CommandMenu("Archive") {
             archiveButton("Go Back", shortcut: Shortcuts.goBack) { tab in
                 if tab.canGoBack {
                     tab.webView.goBack()
                 }
             }

             archiveButton("Go Forward", shortcut: Shortcuts.goForward) { tab in
                 if tab.canGoForward {
                     tab.webView.goForward()
                 }
             }

             Divider()

             Button("Close Tab") {
                 Alto.shared.windowManager.window?.state.browserTabsManager.closeCurrentTab()
             }
 //            .keyboardShortcut(Shortcuts.closeTab)
         }

         CommandMenu("Tabs") {
             Button("New Tab") {
                 Alto.shared.windowManager.window?.state.browserTabsManager.createNewTab()
             }
             .keyboardShortcut(Shortcuts.newTab)
         }
     }

     private func archiveButton(
         _ title: String,
         shortcut: KeyboardShortcut,
         action: @escaping (AltoTab) -> ()
     ) -> some View {
         Button(title) {
             if let tab = Alto.shared.windowManager.window?.state.browserTabsManager.currentSpace.currentTab {
                 action(tab)
             }
         }
         .keyboardShortcut(shortcut)
     }
 }
 */

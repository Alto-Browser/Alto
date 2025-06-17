import SwiftUI

@main
struct AltoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No default window
        Settings {
            SettingsView()
        }
        .commands {
            CommandMenu("Browser") {
                Button("Open Command Palette") {
                    if let window = Alto.shared.windowManager.window {
                        window.state.openCommandPalette()
                    }
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("New Tab") {
                    if let window = Alto.shared.windowManager.window {
                        window.state.browserTabsManager.createNewTab()
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                
                Button("Close Tab") {
                    if let window = Alto.shared.windowManager.window {
                        window.state.browserTabsManager.currentSpace.currentTab?.closeTab()
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                
                Button("New Window") {
                    Alto.shared.windowManager.createWindow()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

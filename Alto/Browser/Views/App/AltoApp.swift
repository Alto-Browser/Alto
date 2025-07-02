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
            AppCommands()
        }
    }
}

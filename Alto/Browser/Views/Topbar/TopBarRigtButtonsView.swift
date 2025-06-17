import SwiftUI

struct TopBarRigtButtonsView: View {
    @Environment(AltoState.self) private var altoState
    
    var body: some View {
        HStack {
            AltoButton(action: {altoState.browserTabsManager.createNewTab()}, icon: "plus", active: true)
            AltoButton(action: {Alto.shared.cookieManager.setupCookies(for: altoState.browserTabsManager.currentSpace.currentTab!.webView)}, icon: "circle", active: true)

            // AltoButton(action: {altoState.toggleTopbar()}, icon: "rectangle")
        }
        .padding(.leading, 40)
        .keyboardShortcut(Shortcuts.newTab)// Ensures topbar doesnt feel cramped with buttons and tabs
    }
}

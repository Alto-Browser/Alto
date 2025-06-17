//
import Observation


/// AltoState handles the state for each window specificaly
/// 
/// Allows each window to display a diferent view of the tabs
@Observable
class AltoState {
    var data: Alto
    var sidebar = false
    var Topbar: AltoTopBarViewModel.TopbarState = .active
    var browserTabsManager: BrowserTabsManager = BrowserTabsManager()
    var draggedTab: TabRepresentation?
    var showCommandPalette = false
    
    init() {
        data = Alto.shared
        self.browserTabsManager.state = self
    }
    
    func setup(webView: WKWebView) {
        data.cookieManager.setupCookies(for: webView)
    }
    
    func toggleTopbar() {
        switch Topbar {
        case .hidden:
            Topbar = .active
        case .active:
            Topbar = .hidden
        }
    }
    
    func openCommandPalette() {
        showCommandPalette = true
    }
    
    func closeCommandPalette() {
        showCommandPalette = false
    }

}

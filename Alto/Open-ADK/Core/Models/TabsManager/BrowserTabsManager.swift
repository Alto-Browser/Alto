import SwiftUI
import Observation


/// Manges Tabs for each Window
///
///  Tabs will be stored in Alto in future in order to support tabs being shared between windows (like Arc)
@Observable
class BrowserTabsManager {
    var state: AltoState?
    var favorites = TabLocation()
    var spaceIndex = 0
    var currentSpace: Space {
        return Alto.shared.spaces[spaceIndex]
    }
    // ToDo: make a dedicated search manager
    var searchEngineURL: String {
        switch PreferencesManager.shared.searchEngine {
        case .brave:
            return "https://search.brave.com/"
        case .duckduckgo:
            return "https://duckduckgo.com/?q="
        case .google:
            return "https://www.google.com"
        default:
            return "https://www.google.com"
        }
    }
    
    init(state: AltoState? = nil) {
        self.state = state
        // self.createNewTab()
    }
    
    func createNewTab(url: String? = nil, frame: CGRect = .zero, configuration: WKWebViewConfiguration = AltoWebViewConfigurationBase(), location: Location = .normal) {
        guard let state = self.state else {
            return
        }
        
        let newWebView = AltoWebView(frame: frame, configuration: configuration)
        Alto.shared.cookieManager.setupCookies(for: newWebView)
        
        var tabLocation: TabLocation {
            switch location {
            case .favorite: self.favorites
            case .pinned: self.currentSpace.pinned
            case .normal: self.currentSpace.normal
            }
        }
        let urlString = url ?? searchEngineURL
        
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            newWebView.load(request)
        }
        
        let newTab = AltoTab(webView: newWebView, state: state)
        let tabRep = TabRepresentation(id: newTab.id, index: tabLocation.tabs.count)
        Alto.shared.tabs[newTab.id] = newTab
        tabLocation.appendTabRep(tabRep)
        self.currentSpace.currentTab = newTab
    }
}

extension BrowserTabsManager {
    enum Location {
        case favorite, pinned, normal
    }
}



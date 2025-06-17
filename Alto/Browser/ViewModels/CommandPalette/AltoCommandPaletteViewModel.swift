import SwiftUI
import Foundation
import Observation

/// Alto-specific command palette view model that wraps the shared SearchSuggestionsManager
/// Handles Alto-specific functionality like tab management and search engine preferences
@Observable
class AltoCommandPaletteViewModel {
    private let searchManager = SearchSuggestionsManager()
    private let browserTabsManager: BrowserTabsManager
    private let altoState: AltoState
    
    var searchText: String {
        get { searchManager.searchText }
        set { searchManager.updateSearchText(newValue) }
    }
    
    var suggestions: [SearchSuggestion] {
        searchManager.suggestions
    }
    
    var selectedIndex: Int {
        get { searchManager.selectedIndex }
        set { searchManager.selectedIndex = newValue }
    }
    
    var selectedSuggestion: SearchSuggestion? {
        searchManager.selectedSuggestion
    }
    
    init(browserTabsManager: BrowserTabsManager, altoState: AltoState) {
        self.browserTabsManager = browserTabsManager
        self.altoState = altoState
    }
    
    func updateSearchText(_ text: String) {
        // Check if this is just a display update (to avoid infinite loop)
        if text == searchManager.searchText {
            return
        }
        
        searchManager.updateSearchText(text)
        
        // Only update search engine preference if there are suggestions and text is not empty
        if !text.isEmpty,
           let firstSuggestion = searchManager.suggestions.first,
           firstSuggestion.type == .searchQuery {
            // Update the subtitle to reflect Alto's search engine choice
            let updatedSuggestion = SearchSuggestion(
                title: firstSuggestion.title,
                subtitle: "Search with \(getSearchEngineName())",
                url: firstSuggestion.url,
                type: firstSuggestion.type,
                favicon: firstSuggestion.favicon
            )
            // Avoid direct array mutation - create new array
            var updatedSuggestions = searchManager.suggestions
            updatedSuggestions[0] = updatedSuggestion
            searchManager.suggestions = updatedSuggestions
        }
    }
    
    func selectNext() {
        searchManager.selectNext()
    }
    
    func selectPrevious() {
        searchManager.selectPrevious()
    }
    
    func executeSelected() {
        // Always use the selected suggestion if there's one highlighted
        if !suggestions.isEmpty, let suggestion = selectedSuggestion {
            openSuggestion(suggestion)
        } else if !searchText.isEmpty {
            performSearch(searchText)
        }
    }
    
    private func openSuggestion(_ suggestion: SearchSuggestion) {
        switch suggestion.type {
        case .url, .website:
            browserTabsManager.createNewTab(url: suggestion.url)
        case .searchQuery:
            performSearch(suggestion.title)
        }
        clearAndClose()
    }
    
    private func performSearch(_ query: String) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let searchURL: String
        
        switch PreferencesManager.shared.searchEngine {
        case .brave:
            searchURL = "https://search.brave.com/search?q=\(encodedQuery)"
        case .duckduckgo:
            searchURL = "https://duckduckgo.com/?q=\(encodedQuery)"
        case .google:
            searchURL = "https://www.google.com/search?q=\(encodedQuery)"
        default:
            searchURL = "https://www.google.com/search?q=\(encodedQuery)"
        }
        
        browserTabsManager.createNewTab(url: searchURL)
        clearAndClose()
    }
    
    private func clearAndClose() {
        searchManager.searchText = ""
        searchManager.suggestions = []
        searchManager.selectedIndex = 0
        altoState.closeCommandPalette()
    }
    
    private func getSearchEngineName() -> String {
        switch PreferencesManager.shared.searchEngine {
        case .brave:
            return "Brave"
        case .duckduckgo:
            return "DuckDuckGo"
        case .google:
            return "Google"
        default:
            return "Google"
        }
    }
}
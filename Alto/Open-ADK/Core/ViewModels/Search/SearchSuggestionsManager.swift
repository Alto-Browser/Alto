import SwiftUI
import Foundation
import Observation

/// Core search suggestions manager that can be used by any browser
/// Contains shared business logic for fetching and managing search suggestions
@Observable
class SearchSuggestionsManager {
    var searchText: String = ""
    var suggestions: [SearchSuggestion] = []
    var selectedIndex: Int = 0
    private var searchTask: Task<Void, Never>?
    private var originalSearchText: String = ""
    
    var selectedSuggestion: SearchSuggestion? {
        guard selectedIndex < suggestions.count else { return nil }
        return suggestions[selectedIndex]
    }
    
    func updateSearchText(_ text: String) {
        searchText = text
        originalSearchText = text
        selectedIndex = 0
        
        searchTask?.cancel()
        
        if text.isEmpty {
            suggestions = []
            return
        }
        
        searchTask = Task {
            // Add debouncing to reduce rapid updates
            try? await Task.sleep(for: .milliseconds(150))
            await updateSuggestions(for: text)
        }
    }
    
    func selectNext() {
        guard !suggestions.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, suggestions.count - 1)
        updateDisplayText()
    }
    
    func selectPrevious() {
        selectedIndex = max(selectedIndex - 1, 0)
        updateDisplayText()
    }
    
    private func updateDisplayText() {
        if selectedIndex == 0 {
            // First item selected, show original search text
            searchText = originalSearchText
        } else if let suggestion = selectedSuggestion {
            // Show the selected suggestion's title
            searchText = suggestion.title
        }
    }
    
    @MainActor
    private func updateSuggestions(for text: String) async {
        var newSuggestions: [SearchSuggestion] = []
        
        // Check if it's a URL
        if isURL(text) {
            let urlSuggestion = SearchSuggestion(
                title: text,
                subtitle: "Go to URL",
                url: normalizeURL(text),
                type: .url
            )
            newSuggestions.append(urlSuggestion)
        } else {
            // Add search query suggestion
            let searchSuggestion = SearchSuggestion(
                title: text,
                subtitle: "Search with Google", // Generic default
                url: text,
                type: .searchQuery
            )
            newSuggestions.append(searchSuggestion)
            
            // Fetch Google suggestions
            let googleSuggestions = await fetchGoogleSuggestions(for: text)
            newSuggestions.append(contentsOf: googleSuggestions)
        }
        
        // Update suggestions only once at the end
        let finalSuggestions = Array(newSuggestions.prefix(5))
        if suggestions != finalSuggestions {
            suggestions = finalSuggestions
        }
    }
    
    private func isURL(_ text: String) -> Bool {
        // Simple URL detection
        let lowercased = text.lowercased()
        return lowercased.hasPrefix("http://") || 
               lowercased.hasPrefix("https://") || 
               lowercased.contains(".") && !lowercased.contains(" ")
    }
    
    private func normalizeURL(_ text: String) -> String {
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return text
        }
        return "https://\(text)"
    }
    
    private func fetchGoogleSuggestions(for query: String) async -> [SearchSuggestion] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        
        let urlString = "https://suggestqueries.google.com/complete/search?output=toolbar&hl=en&q=\(encodedQuery)"
        guard let url = URL(string: urlString) else { 
            return [] 
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Parse XML response from toolbar output format
            if let xmlString = String(data: data, encoding: .utf8) {
                return parseXMLSuggestions(xmlString)
            }
        } catch {
            // Silently handle network errors
        }
        
        return []
    }
    
    private func parseXMLSuggestions(_ xmlString: String) -> [SearchSuggestion] {
        var suggestions: [SearchSuggestion] = []
        
        // Simple XML parsing to extract suggestion attributes
        let pattern = #"<suggestion data="([^"]*)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))
        
        for match in matches?.prefix(5) ?? [] {
            if let range = Range(match.range(at: 1), in: xmlString) {
                let suggestionText = String(xmlString[range])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                
                suggestions.append(SearchSuggestion(
                    title: suggestionText,
                    subtitle: nil,
                    url: suggestionText,
                    type: .searchQuery
                ))
            }
        }
        
        return suggestions
    }
}
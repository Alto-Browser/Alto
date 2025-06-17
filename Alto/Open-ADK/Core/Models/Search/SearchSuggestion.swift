import SwiftUI
import Foundation

struct SearchSuggestion: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let url: String
    let type: SuggestionType
    let favicon: Image?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(subtitle)
        hasher.combine(url)
        hasher.combine(type)
    }
    
    static func == (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.url == rhs.url &&
        lhs.type == rhs.type
    }
    
    enum SuggestionType {
        case url
        case searchQuery
        case website
    }
    
    var displayIcon: String {
        switch type {
        case .url:
            return "globe"
        case .searchQuery:
            return "magnifyingglass"
        case .website:
            return "globe"
        }
    }
    
    init(title: String, subtitle: String? = nil, url: String, type: SuggestionType, favicon: Image? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.type = type
        self.favicon = favicon
    }
}
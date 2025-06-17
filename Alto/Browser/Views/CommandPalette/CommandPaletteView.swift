import SwiftUI

struct CommandPaletteView: View {
    @State private var viewModel: AltoCommandPaletteViewModel
    @FocusState private var isSearchFocused: Bool
    private let altoState: AltoState
    
    init(altoState: AltoState) {
        self.altoState = altoState
        self._viewModel = State(initialValue: AltoCommandPaletteViewModel(browserTabsManager: altoState.browserTabsManager, altoState: altoState))
    }
    
    var body: some View {
        ZStack {
                // Background overlay
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        altoState.closeCommandPalette()
                    }
                
                // Palette content positioned at top
                VStack {
                    VStack(spacing: 0) {
                        // Search field
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16, weight: .medium))
                            
                            TextField("Search or enter address", text: $viewModel.searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 16, weight: .regular))
                                .focused($isSearchFocused)
                                .onSubmit {
                                    viewModel.executeSelected()
                                }
                                .onChange(of: viewModel.searchText) { _, newValue in
                                    viewModel.updateSearchText(newValue)
                                }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        
                        // Suggestions list
                        if !viewModel.suggestions.isEmpty {
                            // Subtle separator line
                            Divider()
                                .frame(height: 0.5)
                                .background(Color.secondary.opacity(0.1))
                                .padding(.horizontal, 20)
                            
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                                    SuggestionRow(
                                        suggestion: suggestion,
                                        isSelected: index == viewModel.selectedIndex
                                    )
                                    .id("\(suggestion.id)-\(index)")
                                    .onTapGesture {
                                        viewModel.selectedIndex = index
                                        viewModel.executeSelected()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: 580)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 12)
                    .animation(.spring.speed(2.0), value: viewModel.suggestions)
                    
                    Spacer()
                }
                .padding(.top, 250)
            }
            .onKeyPress(.downArrow) {
                viewModel.selectNext()
                return .handled
            }
            .onKeyPress(.upArrow) {
                viewModel.selectPrevious()
                return .handled
            }
            .onKeyPress(.escape) {
                altoState.closeCommandPalette()
                return .handled
            }
            .onAppear {
                if altoState.showCommandPalette {
                    isSearchFocused = true
                    viewModel.searchText = ""
                }
            }
            .opacity(altoState.showCommandPalette ? 1 : 0)
            .allowsHitTesting(altoState.showCommandPalette)
    }
}

struct SuggestionRow: View {
    let suggestion: SearchSuggestion
    let isSelected: Bool
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            Image(systemName: suggestion.displayIcon)
                .foregroundColor(.secondary)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 16, height: 16)
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsHitTesting(false)
                
                if let subtitle = suggestion.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .allowsHitTesting(false)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.15), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 4)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.05))
                        .padding(.horizontal, 4)
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

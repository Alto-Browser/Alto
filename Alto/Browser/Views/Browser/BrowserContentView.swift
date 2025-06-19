import OpenADK
import SwiftUI

struct BrowserContentView: View {
    @Environment(AltoState.self) private var altoState
    @Bindable var preferences: PreferencesManager = .shared

    var body: some View {
        ZStack {
            if preferences.sidebarPosition == .left || preferences.sidebarPosition == .right {
                // Sidebar layout
                HStack(spacing: 0) {
                    if preferences.sidebarPosition == .left {
                        sidebarLayout
                        mainContentArea
                    } else {
                        mainContentArea
                        sidebarLayout
                    }
                }
            } else {
                // Original horizontal layout
                VStack(spacing: 5) {
                    if altoState.Topbar == .active {
                        AltoTopBar(model: AltoTopBarViewModel(state: altoState))
                    }

                    ZStack {
                        let currentContent = altoState.currentContent

                        if let currentContent {
                            ForEach(Array(currentContent.enumerated()), id: \.element.id) { _, content in
                                AnyView(content.returnView())
                                    .cornerRadius(10)
                            }
                        } else {
                            Image("Logo")
                                .opacity(0.5)
                                .blendMode(.softLight)
                                .scaleEffect(1.3)
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
                .padding(5)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var sidebarLayout: some View {
        // Sidebar with tabs
        VStack(spacing: 0) {
            // Top bar controls (back/forward buttons, etc.)
            HStack(spacing: 2) {
                MacButtonsView()
                    .padding(.leading, 6)
                    .frame(width: 70)

                AltoButton(
                    action: {
                        altoState.currentSpace?.currentTab?.content[0].goBack()
                    },
                    icon: "arrow.left",
                    active: altoState.currentSpace?.currentTab?.content[0].canGoBack ?? false
                )
                .frame(height: 30)
                .fixedSize()

                AltoButton(
                    action: {
                        altoState.currentSpace?.currentTab?.content[0].goForward()
                    },
                    icon: "arrow.right",
                    active: altoState.currentSpace?.currentTab?.content[0].canGoForward ?? false
                )
                .frame(height: 30)
                .fixedSize()

                Spacer()
            }
            .frame(height: 30)
            .padding(.horizontal, 5)

            // Sidebar tabs
            if let location = altoState.currentSpace?.localLocations[1] {
                SidebarTabView(model: DropZoneViewModel(
                    state: altoState,
                    tabLocation: location
                ))
            }
        }
        .frame(width: 200)
    }

    @ViewBuilder
    private var mainContentArea: some View {
        // Main content area
        VStack(spacing: 0) {
            // Address bar area
            HStack {
                Spacer()
                TopBarRigtButtonsView()
                    .frame(height: 30)
                    .fixedSize()
            }
            .frame(height: 30)
            .padding(.horizontal, 5)

            // Web view
            ZStack {
                let currentContent = altoState.currentContent

                if let currentContent {
                    ForEach(Array(currentContent.enumerated()), id: \.element.id) { _, content in
                        AnyView(content.returnView())
                            .cornerRadius(10)
                    }
                }

                if currentContent == nil {
                    Image("Logo")
                        .opacity(0.5)
                        .blendMode(.softLight)
                        .scaleEffect(1.3)
                }
            }
            .padding(.leading, 5)
            .padding(.trailing, 5)
            .padding(.bottom, 5)
        }
    }
}

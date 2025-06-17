import SwiftUI





struct AltoTopBar: View {
    var model: AltoTopBarViewModel
    
    var body: some View {
            HStack (spacing: 2) {
                
                // MacButtonsViewNew()
                MacButtonsView()
                    .padding(.leading, 6)
                    .frame(width: 70)
                
                // ToDo: add spaces dropdown
                AltoButton(action: {
                    model.currentTab?.webView.goBack()
                }, icon: "arrow.left", active: model.currentTab?.canGoBack ?? false)
                .frame(height: 30)
                .fixedSize()
                .keyboardShortcut(Shortcuts.goBack)
                .keyboardShortcut(Shortcuts.goBackAlt)
                
                AltoButton(action: {
                    model.currentTab?.webView.goForward()
                }, icon: "arrow.right", active: model.currentTab?.canGoForward ?? false)
                .frame(height: 30)
                .fixedSize()
                .keyboardShortcut(Shortcuts.goForward)
                .keyboardShortcut(Shortcuts.goForwardAlt)
                
                FavoriteDropZoneView(model:FavoriteDropZoneViewModel(state: model.state, tabLocation: model.state.browserTabsManager.favorites))
                    .frame(height: 30)
                    .fixedSize()
                
                if model.state.browserTabsManager.favorites.tabs.count > 0 {
                    Divider().frame(width: 2)
                }
                
                DropZoneView(model: DropZoneViewModel(state: model.state, tabLocation: model.state.browserTabsManager.currentSpace.normal))
                    .frame(height: 30)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                
                TopBarRigtButtonsView()
                    .frame(height: 30)
                    .fixedSize()
                   
            }
            .frame(height: 30)
    }
}



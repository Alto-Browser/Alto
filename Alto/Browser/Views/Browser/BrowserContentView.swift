import SwiftUI


struct BrowserContentView: View {
    @Environment(AltoState.self) private var altoState
    
    var body: some View {
        ZStack {
            VStack (spacing: 5) {
                if altoState.Topbar == .active {
                    AltoTopBar(model: AltoTopBarViewModel(state: altoState))
                }
                
                ZStack {
                    let currentTab = altoState.browserTabsManager.currentSpace.currentTab
                    
                    NSWebView(webView: currentTab?.webView)
                        .id(currentTab?.id)
                        .cornerRadius(10)
                    
                    if currentTab == nil {
                        Image("Logo")
                            .opacity(0.5)
                            .blendMode(.softLight)
                            .scaleEffect(1.3)
                    }
                }
            }
            .padding(5)
            
            // Command Palette Overlay
            CommandPaletteView(altoState: altoState)
        }
        .ignoresSafeArea()
    }
}

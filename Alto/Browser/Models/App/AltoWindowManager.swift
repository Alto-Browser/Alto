//
import OpenADK
import SwiftUI

@Observable
open class AltoWindowManager {
    public static let shared = AltoWindowManager()

    public var defaultConfig: DefaultWindowConfiguration = .init()

    public var windows: [ADKWindow] = []

    private var defaultProfile: Profile {
        ProfileManager.shared.defaultProfile
    }

    public init() {}

    @discardableResult
    open func createWindow(
        profile: Profile? = nil,
        tabs: [ADKTab] = [],
        contentRect: NSRect? = nil
    ) -> ADKWindow? {
        let viewState = AltoState()

        let contentView = BrowserView()
            .environment(viewState)

        let hostingController = NSHostingView(rootView: contentView)

        let window = AltoWindow(
            rootView: hostingController,
            state: viewState
        )

        windows.append(window)
        window.orderFront(nil)
        return window
    }
}

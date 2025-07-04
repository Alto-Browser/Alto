import SwiftUI

// MARK: - FavoriteView

struct FavoriteView: View {
    var model: TabViewModel
    @State var isHovered = false
    var body: some View {
        HStack {
            model.tabIcon
                .resizable()
                .scaledToFit()
        }
        .padding(4)
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .draggable(model.tab) {
            Rectangle()
                .fill(.red)
                .opacity(1)
        }
        .gesture(
            TapGesture(count: 2).onEnded {}
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                model.handleSingleClick()
            }
        )
        .background(
            Rectangle()
                .fill(.white.opacity(0.2))
                .cornerRadius(5)
        )
        .onHover { _ in
        }
    }
}

// MARK: - AltoFavoriteView

struct AltoFavoriteView: View {
    var model: TabViewModel

    var body: some View {
        HStack {
            faviconImage(model: model)
        }
        .padding(4)
        .frame(width: 150)
        .background(
        )
        .contentShape(Rectangle()) // Makes the background clickable
        .gesture(
            TapGesture(count: 2).onEnded {
                model.handleDoubleClick()
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                model.handleSingleClick()
            }
        )
        .draggable(model.tab) {
            AltoTabViewDragged(model: model)
        }
    }
}

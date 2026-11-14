import SwiftUI

struct BookDrawer: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let theme: Theme
    let width: CGFloat
    @Binding var drag: CGFloat
    @State private var closing: Bool?

    private var visibleWidth: CGFloat {
        min(max((store.booksOpen ? width : 0) + drag, 0), width)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.16 * visibleWidth / max(width, 1))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
                .accessibilityLabel("Close books")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("books-backdrop")
                .accessibilityHidden(!store.booksOpen)
                .allowsHitTesting(store.booksOpen)

            BookPicker(theme: theme, close: close)
                .id(store.booksOpen || drag > 0)
                .frame(width: width)
                .background(Color(theme.paper).ignoresSafeArea())
                .offset(x: visibleWidth - width)
                .accessibilityAddTraits(.isModal)
                .accessibilityHidden(!store.booksOpen)
                .accessibilityAction(.escape, close)
                .allowsHitTesting(store.booksOpen)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            if closing == nil {
                                closing = value.translation.width < -abs(value.translation.height) * 1.5
                            }
                            guard closing == true else { return }
                            drag = min(value.translation.width, 0)
                        }
                        .onEnded { value in
                            let wasClosing = closing == true
                            closing = nil
                            guard wasClosing else { return }
                            let projected = value.predictedEndTranslation.width
                            withAnimation(animation) {
                                if -projected > width * 0.4 { store.booksOpen = false }
                                drag = 0
                            }
                        }
                )
        }
        .animation(animation, value: store.booksOpen)
        .onChange(of: store.booksOpen) { _, open in
            if !open { closing = nil }
        }
    }

    private var animation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.28)
    }

    private func close() {
        withAnimation(animation) {
            store.booksOpen = false
            drag = 0
        }
    }
}

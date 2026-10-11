import SwiftUI

/// Shows `MenuView` as a side drawer: it slides in from the leading edge (left in left-to-right
/// languages, right in Arabic) over part of the screen and dims the rest. Tapping the dimmed
/// area, the close button, or swiping the drawer back towards its edge closes it.
struct MenuDrawer: View {
    @Binding var isPresented: Bool
    @Environment(\.layoutDirection) private var layoutDirection
    /// Resets (with a spring back) if the system cancels the drag, so the drawer never sticks
    /// half-open.
    @GestureState(resetTransaction: Transaction(animation: .snappy)) private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = Self.width(inContainer: proxy.size.width)
            let progress = 1 - min(abs(dragOffset) / width, 1)

            ZStack(alignment: .leading) {
                if isPresented {
                    Theme.Palette.scrim
                        .opacity(0.55 * progress)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: close)
                        .accessibilityHidden(true)
                        .transition(.opacity)

                    MenuView(onClose: close)
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .background {
                            UnevenRoundedRectangle(bottomTrailingRadius: Theme.Radius.popover, topTrailingRadius: Theme.Radius.popover)
                                .fill(Theme.Palette.background)
                                .shadow(color: .black.opacity(0.3), radius: 24)
                                .ignoresSafeArea()
                        }
                        .offset(x: dragOffset)
                        // Simultaneous, so the menu's scroll view doesn't swallow the swipe.
                        .simultaneousGesture(drag(width: width))
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape, close)
                        .transition(.move(edge: .leading))
                }
            }
        }
    }

    /// Most of a phone's width, leaving a strip of the screen visible; capped on wider windows.
    static func width(inContainer containerWidth: CGFloat) -> CGFloat {
        min(containerWidth * 0.82, 340)
    }

    /// Follows mostly-horizontal drags towards the leading edge only, and closes past a third
    /// of the width or on a quick flick. `dragOffset` is negative towards the leading edge.
    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragOffset) { value, offset, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(towardsTrailing(value.translation.width), 0)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if towardsTrailing(value.translation.width) < -width / 3
                    || towardsTrailing(value.predictedEndTranslation.width) < -width / 2 {
                    close()
                }
            }
    }

    /// Drag translations are in screen terms (positive is rightwards) even in right-to-left
    /// layouts, while `offset` is mirrored there (positive is towards the trailing edge).
    private func towardsTrailing(_ x: CGFloat) -> CGFloat {
        layoutDirection == .rightToLeft ? -x : x
    }

    private func close() {
        withAnimation(.snappy) { isPresented = false }
    }
}

import SwiftUI

#if os(macOS)

// MacGlassScene — the macOS window scaffold (HANDOFF §2.6 SwiftUI hints).
//
// ZStack layering:
//   1. BloomBackground at the very bottom (colored blobs for glass refraction),
//   2. full-width content ScrollView (content starts ~226pt from the left so it
//      clears the floating sidebar; the sidebar glass sits OVER it and refracts
//      the window's blooms behind it),
//   3. `.overlay` the FloatingSidebar, sized to wrap its content via
//      `.frame(maxHeight: .infinity)` + centered, `.padding(.leading, 14)`.
//
// Traffic lights float at the window's top-left (standard `.hiddenTitleBar`
// window — set by the App scene).

struct MacGlassScene<Content: View>: View {
    @Binding var selection: SidebarDestination
    var onAddEntry: () -> Void
    @ViewBuilder var content: () -> Content

    /// Content left inset so the full-width content clears the floating sidebar.
    private let contentLeadingInset: CGFloat = 226

    var body: some View {
        ZStack(alignment: .leading) {
            BloomBackground()

            ScrollView {
                content()
                    .padding(.leading, contentLeadingInset)
                    .padding(.trailing, 28)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .leading) {
            FloatingSidebar(selection: $selection, onAddEntry: onAddEntry)
                .padding(.leading, 14)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        // Wide enough that the dual-currency hero (two ~66pt figures + divider)
        // lays out side by side at full size without the amounts having to shrink.
        .frame(minWidth: 1160, minHeight: 680)
    }
}

#endif

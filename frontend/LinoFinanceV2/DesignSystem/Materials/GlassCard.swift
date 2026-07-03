import SwiftUI

// GlassCard — HANDOFF §2.5.
//
// Real Liquid Glass: `.glassEffect(in: .rect(cornerRadius:))` (NOT v1's
// `.ultraThinMaterial`). On top of the glass we layer:
//   • a 0.5pt white inset highlight along the top edge,
//   • a 0.5pt hairline border,
//   • a soft, large, low-opacity shadow (card: y9 / blur26 / black 8%).
//
// Deploy target is macOS 26 / iOS 26 so `.glassEffect` is always available — no
// `<26` fallback branch (decision D3).

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    var padding: CGFloat = 18
    var shadow: Theme.ShadowSpec = Theme.Shadow.card
    /// Optional brand tint washed faintly over the glass (net-worth / AI cards).
    var tint: Color? = nil
    /// v2.5.0 评审修补 · D: when true, the glass background itself stretches to
    /// fill an externally-imposed height (e.g. a sibling in an equal-height
    /// HStack) instead of hugging its content. Must be applied INSIDE
    /// `.glassEffect` — an outer `.frame(maxHeight:.infinity)` on the whole
    /// card only fills the HStack's layout slot, not the visible glass shape
    /// (reviewer 重要-1). Default false = existing hug-content behavior,
    /// zero impact on other GlassCard call sites.
    var fillsHeight: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content()
            .padding(padding)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: fillsHeight ? .topLeading : .leading
            )
            .glassEffect(in: shape)
            .overlay {
                if let tint {
                    shape.fill(tint.opacity(0.12))
                }
            }
            .overlay {
                // 0.5pt top inset white highlight — fades from top to nothing.
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.Color.glassHighlight, .clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.5
                    )
            }
            .overlay {
                // 0.5pt hairline border.
                shape.strokeBorder(Theme.Color.glassStroke, lineWidth: 0.5)
            }
            .themeShadow(shadow)
    }
}

extension View {
    /// Wrap an existing view in the v2 glass treatment without re-padding it.
    func glassPanel(
        cornerRadius: CGFloat = Theme.Radius.card,
        shadow: Theme.ShadowSpec = Theme.Shadow.card,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .glassEffect(in: shape)
            .overlay {
                if let tint { shape.fill(tint.opacity(0.12)) }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Theme.Color.glassHighlight, .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 0.5
                )
            }
            .overlay { shape.strokeBorder(Theme.Color.glassStroke, lineWidth: 0.5) }
            .themeShadow(shadow)
    }
}

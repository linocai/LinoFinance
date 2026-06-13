import SwiftUI

// BloomBackground — HANDOFF §2.3.
//
// Three soft colored radial blobs (orange / blue / violet) under a heavy gaussian
// blur, sitting at the very bottom of the z-stack so the glass layers above have
// COLOR to refract. Without this, `.glassEffect` reads grey and dead.
//
// In dark mode the canvas base is a near-black radial gradient (#1C1D24 → #0A0A0C);
// in light mode it is a soft off-white wash. The blooms keep a slightly higher
// opacity in dark mode so they still bleed through.

struct BloomBackground: View {
    /// Enable an extremely slow drift animation. Default on; disable for static
    /// previews/screenshots where motion is undesirable.
    var animated: Bool = true

    @Environment(\.colorScheme) private var scheme
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                canvasBase

                blob(Theme.Bloom.orange, opacity: scheme == .dark ? 0.42 : 0.35)
                    .frame(width: w * 0.75, height: w * 0.75)
                    .position(x: w * (drift ? 0.20 : 0.16), y: h * (drift ? 0.20 : 0.16))

                blob(Theme.Bloom.blue, opacity: scheme == .dark ? 0.46 : 0.38)
                    .frame(width: w * 0.85, height: w * 0.85)
                    .position(x: w * (drift ? 0.86 : 0.90), y: h * (drift ? 0.30 : 0.26))

                blob(Theme.Bloom.violet, opacity: scheme == .dark ? 0.38 : 0.30)
                    .frame(width: w * 0.80, height: w * 0.80)
                    .position(x: w * (drift ? 0.72 : 0.78), y: h * (drift ? 0.86 : 0.90))
            }
            .blur(radius: 60)
        }
        .ignoresSafeArea()
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private var canvasBase: some View {
        Group {
            if scheme == .dark {
                RadialGradient(
                    colors: [Theme.fixed(0x1C1D24), Theme.fixed(0x0A0A0C)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 900
                )
            } else {
                LinearGradient(
                    colors: [Theme.fixed(0xF7F8FB), Theme.fixed(0xEEF0F6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private func blob(_ color: Color, opacity: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 260
                )
            )
    }
}

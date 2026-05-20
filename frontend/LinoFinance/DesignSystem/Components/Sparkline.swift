import SwiftUI

struct Sparkline: View {
    let values: [Double]
    var tint: Color = FinanceTokens.Brand.primary

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let points = normalizedPoints(in: geometry.size)
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(minHeight: 38)
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else {
            return [
                CGPoint(x: 0, y: size.height / 2),
                CGPoint(x: size.width, y: size.height / 2),
            ]
        }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let range = max(maximum - minimum, 0.0001)
        return values.enumerated().map { index, value in
            let x = size.width * Double(index) / Double(max(values.count - 1, 1))
            let y = size.height - ((value - minimum) / range * size.height)
            return CGPoint(x: x, y: y)
        }
    }
}

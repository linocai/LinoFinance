import SwiftUI

/// 带渐变 area fill 的 sparkline —— 对齐 HTML iOS Hero 的 `<svg class="sparkline">`：
/// 上面是 brand 蓝色折线，下方是渐变区域 fill（顶部 brand 45% → 底部 0%）。
/// 与原 `Sparkline`（只画线）并存：feature 行可以继续用 Sparkline，iOS hero 用这个。
struct SparklineCanvasView: View {
    let values: [Double]
    var tint: Color = FinanceTokens.Brand.primary
    var lineWidth: CGFloat = 2

    var body: some View {
        Canvas { ctx, size in
            let points = normalizedPoints(in: size)
            guard points.count > 1 else { return }

            // Area fill
            var areaPath = Path()
            areaPath.move(to: CGPoint(x: points.first!.x, y: size.height))
            areaPath.addLine(to: points.first!)
            for point in points.dropFirst() {
                areaPath.addLine(to: point)
            }
            areaPath.addLine(to: CGPoint(x: points.last!.x, y: size.height))
            areaPath.closeSubpath()
            ctx.fill(
                areaPath,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.45), tint.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            // Line
            var linePath = Path()
            linePath.move(to: points[0])
            for point in points.dropFirst() {
                linePath.addLine(to: point)
            }
            ctx.stroke(linePath, with: .color(tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else {
            return values.isEmpty ? [] : [
                CGPoint(x: 0, y: size.height / 2),
                CGPoint(x: size.width, y: size.height / 2)
            ]
        }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let range = max(maximum - minimum, 0.0001)
        let topPadding: CGFloat = 4
        let bottomPadding: CGFloat = 6
        let usableHeight = max(size.height - topPadding - bottomPadding, 1)
        return values.enumerated().map { index, value in
            let x = size.width * Double(index) / Double(max(values.count - 1, 1))
            let normalized = (value - minimum) / range
            let y = size.height - bottomPadding - normalized * usableHeight
            return CGPoint(x: x, y: y)
        }
    }
}

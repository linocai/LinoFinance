import SwiftUI

/// 应用根部背景 —— 对齐 HTML `--bg-canvas`：
/// 浅色顶→底线性渐变，深色 20%/0% 径向渐变。一次性绘制在 root，所有透明 surface 都受益。
struct CanvasBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(fill)
            .ignoresSafeArea()
    }

    private var fill: AnyShapeStyle {
        switch scheme {
        case .dark:
            return AnyShapeStyle(
                RadialGradient(
                    colors: [
                        Color(red: 0.106, green: 0.114, blue: 0.149),
                        Color(red: 0.031, green: 0.031, blue: 0.047)
                    ],
                    center: UnitPoint(x: 0.2, y: 0),
                    startRadius: 0,
                    endRadius: 1200
                )
            )
        default:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.973, green: 0.973, blue: 0.988),
                        Color(red: 0.933, green: 0.941, blue: 0.965)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

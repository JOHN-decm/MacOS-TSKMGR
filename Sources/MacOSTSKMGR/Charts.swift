import SwiftUI

struct GridChart: View {
    @Environment(\.colorScheme) private var colorScheme
    let values: [Double]
    let color: Color
    var verticalSteps: Int = 8
    var horizontalSteps: Int = 6
    var lineWidth: CGFloat = 1.25
    var filled: Bool = false
    var ceiling: Double = 100
    var fillOpacityMultiplier: Double = 1

    private var normalized: [CGPoint] {
        guard !values.isEmpty else { return [] }
        let maxX = max(Double(values.count - 1), 1)
        return values.enumerated().map { index, value in
            CGPoint(x: Double(index) / maxX, y: min(max(value / ceiling, 0), 1))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    for step in 0...verticalSteps {
                        let x = width * CGFloat(step) / CGFloat(verticalSteps)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                    for step in 0...horizontalSteps {
                        let y = height * CGFloat(step) / CGFloat(horizontalSteps)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(AppTheme.chartGrid(colorScheme, accent: color), lineWidth: 0.7)

                if filled {
                    Path { path in
                        guard let first = normalized.first else { return }
                        path.move(to: CGPoint(x: 0, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: first.x * proxy.size.width, y: proxy.size.height * (1 - first.y)))
                        for point in normalized {
                            path.addLine(to: CGPoint(x: point.x * proxy.size.width, y: proxy.size.height * (1 - point.y)))
                        }
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(AppTheme.chartFill(colorScheme, accent: color).opacity(fillOpacityMultiplier))
                }

                Path { path in
                    guard let first = normalized.first else { return }
                    path.move(to: CGPoint(x: first.x * proxy.size.width, y: proxy.size.height * (1 - first.y)))
                    for point in normalized.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x * proxy.size.width, y: proxy.size.height * (1 - point.y)))
                    }
                }
                .stroke(color, lineWidth: lineWidth)
            }
        }
    }
}

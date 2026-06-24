import SwiftUI
import AppKit

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = emphasized
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat
    var material: NSVisualEffectView.Material
    var tint: Color = .white.opacity(0.18)
    var stroke: Color = .white.opacity(0.55)

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .background(
                        VisualEffectBlur(material: material, blendingMode: .withinWindow)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        (colorScheme == .dark ? tint.opacity(0.42) : tint.opacity(0.9)),
                                        (colorScheme == .dark ? tint.opacity(0.14) : tint.opacity(0.35))
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 8)
            }
    }
}

extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = 18,
        material: NSVisualEffectView.Material = .underWindowBackground,
        tint: Color = .white.opacity(0.16),
        stroke: Color = .white.opacity(0.52)
    ) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, material: material, tint: tint, stroke: stroke))
    }

    func winMenuPanel() -> some View {
        modifier(ThemeMenuPanelModifier())
    }
}

private struct ThemeMenuPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectBlur(material: .menu, blendingMode: .withinWindow)
                    AppTheme.menuPanelOverlay(colorScheme)
                }
            )
            .overlay(
                Rectangle()
                    .stroke(AppTheme.menuPanelStroke(colorScheme), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}

import SwiftUI
import AppKit

enum AppTheme {
    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.56)
    }

    static func windowTop(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.94)
            : Color.white.opacity(0.88)
    }

    static func windowBottom(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.92)
            : Color(red: 0.94, green: 0.97, blue: 1.0).opacity(0.72)
    }

    static func topGlow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.42)
    }

    static func chromeBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.06)
    }

    static func chromeSelectedFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accentBlue.opacity(0.18) : Color.white.opacity(0.76)
    }

    static let accentBlue = Color(red: 0.22, green: 0.58, blue: 1.0)
    static let accentBlueSoft = Color(red: 0.58, green: 0.80, blue: 1.0)

    static func menuHighlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accentBlue.opacity(0.24) : Color(red: 0.75, green: 0.88, blue: 1.0)
    }

    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    static func strongSeparator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.16)
    }

    static func tableHeader(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.92)
    }

    static func tableMetricHeader(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.78)
    }

    static func tableHeaderStrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.96)
    }

    static func rowEven(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.26)
    }

    static func rowOdd(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.14) : Color.black.opacity(0.025)
    }

    static func selectedRow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? accentBlue.opacity(0.28)
            : Color(red: 0.84, green: 0.91, blue: 0.98).opacity(0.95)
    }

    static func footerButtonFill(_ scheme: ColorScheme, enabled: Bool) -> Color {
        if scheme == .dark {
            return enabled ? Color.white.opacity(0.10) : Color.white.opacity(0.04)
        }
        return enabled ? Color.white.opacity(0.42) : Color.white.opacity(0.18)
    }

    static func footerStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.66)
    }

    static func compactFooterFill(_ scheme: ColorScheme, enabled: Bool) -> Color {
        if scheme == .dark {
            return enabled ? Color.white.opacity(0.10) : Color.white.opacity(0.04)
        }
        return enabled ? Color(nsColor: .controlBackgroundColor).opacity(0.86) : Color(nsColor: .controlBackgroundColor).opacity(0.42)
    }

    static func compactFooterStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    static func chartGrid(_ scheme: ColorScheme, accent: Color) -> Color {
        scheme == .dark ? accent.opacity(0.28) : accent.opacity(0.18)
    }

    static func chartFill(_ scheme: ColorScheme, accent: Color) -> Color {
        scheme == .dark ? accent.opacity(0.16) : accent.opacity(0.08)
    }

    static func fallbackIconFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.gray.opacity(0.26)
    }

    static func menuPanelOverlay(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.78) : Color.white.opacity(0.82)
    }

    static func menuPanelStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.20)
    }
}

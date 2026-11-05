import SwiftUI

/// Single source of truth for the brand palette. Reference these tokens everywhere,
/// never raw `Color` literals (see the `mobile-ios-design` skill).
enum Theme {
    static let primary = Color(hex: 0x7C5CFF)     // violet — Obsidian-flavoured accent
    static let secondary = Color(hex: 0x4C8DFF)   // blue — links / selected
    static let highlight = Color(hex: 0xFFB020)   // amber — badges / highlights

    // The app defaults to the light appearance (see `AppAppearance`); the brand violet works
    // as the accent in both light and dark.
    static let accent = primary
    static let onAccent = Color.white             // text and icons on an accent fill

    #if os(macOS)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .underPageBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    #else
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    #endif

    static let ink = Color.primary
    static let mutedInk = Color.secondary
    static let hairline = Color.primary.opacity(0.08)
}

/// The user's appearance choice (Settings → Appearance). Light is the default.
/// HTML pages follow it too: WKWebView reports it to `prefers-color-scheme`.
enum AppAppearance: String, CaseIterable, Identifiable {
    case light, dark, system

    static let storageKey = "appearance.theme"
    static let defaultValue = AppAppearance.light

    var id: String { rawValue }
    var title: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }
    var symbol: String {
        switch self {
        case .light:  return "sun.max"
        case .dark:   return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }
    /// For `.preferredColorScheme` (nil = follow the system).
    var colorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? defaultValue
    }

    #if os(macOS)
    /// Applies the choice app-wide (windows, sheets, alerts, web views). Using NSApp's
    /// appearance rather than `.preferredColorScheme` so "System" really reverts.
    func apply() {
        switch self {
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }
    #endif
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Reusable elevated card surface — white/elevated, continuous corners, hairline border.
struct AppCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
    }
}

extension View {
    func appCard(padding: CGFloat = 16) -> some View { modifier(AppCard(padding: padding)) }
}

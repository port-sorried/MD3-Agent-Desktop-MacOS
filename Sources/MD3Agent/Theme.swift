import SwiftUI
import AppKit

enum Theme {
    // BrandColors.kt is the source of truth for the Material 3 brand palette.
    static let primary = adaptive(light: 0x455D93, dark: 0xB0C6FF)
    static let onPrimary = adaptive(light: 0xFFFFFF, dark: 0x152E60)
    static let surface = adaptive(light: 0xFAF8FF, dark: 0x121318)
    static let surfaceContainer = adaptive(light: 0xEEEDF4, dark: 0x1E1F25)
    static let surfaceContainerHigh = adaptive(light: 0xE8E7EF, dark: 0x282A2F)
    static let surfaceContainerHighest = adaptive(light: 0xE2E2E9, dark: 0x33353A)
    static let onSurface = adaptive(light: 0x1A1B20, dark: 0xE3E2E9)
    static let onSurfaceVariant = adaptive(light: 0x44474F, dark: 0xC4C6D0)
    static let outline = adaptive(light: 0x74777F, dark: 0x8E9099)
    static let error = Color(nsColor: .systemRed)
    static let primaryContainer = adaptive(light: 0xD9E2FF, dark: 0x2D4578)
    static let onPrimaryContainer = adaptive(light: 0x2D4578, dark: 0xD9E2FF)
    static let secondaryContainer = adaptive(light: 0xDBE2F9, dark: 0x3F4759)
    static let cornerRadius: CGFloat = 28
    static let body = Font.system(size: 15)
    static let title = Font.system(size: 28, weight: .medium, design: .rounded)
    static let code = Font.system(size: 12, design: .monospaced)

    static func scheme(_ preference: String) -> ColorScheme? {
        switch preference { case "light": .light; case "dark": .dark; default: nil }
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct MaterialButtonStyle: ButtonStyle {
    var filled = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .foregroundStyle(filled ? Theme.onPrimary : Theme.onPrimaryContainer)
            .background(filled ? Theme.primary : Theme.secondaryContainer, in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

import SwiftUI
import AppKit

enum Theme {
    static let primary = Color.accentColor
    static let onPrimary = Color.white
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let surfaceContainer = Color(nsColor: .controlBackgroundColor)
    static let onSurface = Color(nsColor: .labelColor)
    static let onSurfaceVariant = Color(nsColor: .secondaryLabelColor)
    static let outline = Color(nsColor: .separatorColor)
    static let error = Color(nsColor: .systemRed)
    static let primaryContainer = Color.accentColor.opacity(0.12)
    static let cornerRadius: CGFloat = 14
    static let body = Font.system(size: 14)
    static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let code = Font.system(size: 12, design: .monospaced)

    static func scheme(_ preference: String) -> ColorScheme? {
        switch preference { case "light": .light; case "dark": .dark; default: nil }
    }
}

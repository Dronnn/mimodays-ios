import SwiftUI

/// The camera's own colours (C01-C05, C13). The camera is dark in both appearances, so these are fixed, not tokens.
public enum CameraPalette {
    public static let background = Color(hex: 0x2A1B21)
    /// Round control backgrounds over the preview: background at 42 %.
    public static let controlScrim = Color(hex: 0x2A1B21).opacity(0.42)
    public static let cream = Color(hex: 0xFBF6EF)
    public static let coral = Color(hex: 0xF06E45)
    public static let recording = Color(hex: 0xBA4923)
    public static let chip = Color(hex: 0xD8DBC1)
    public static let chipText = Color(hex: 0x4B2938)
    public static let star = Color(hex: 0xEE6639)
    public static let thumbnailPlaceholder = Color(hex: 0x7A6658)
    public static let selfiePlaceholder = Color(hex: 0xB5A69A)
    /// Shown until the first preview frame arrives.
    public static let previewPlaceholder = LinearGradient(
        colors: [Color(hex: 0x9A8572), Color(hex: 0x4E3F36)], startPoint: .top, endPoint: .bottom
    )
}

import Foundation

/// P3.4 (Penpot §V3 X01): how big new videos are. Both cameras always record at the same size (P1.0a).
/// High is what MimoDays always recorded; Balanced keeps 1080p at a lower bit rate; Compact is 720p at a lower one
/// still. The bit rates are first numbers, to be checked against clips measured on a phone (P3.1).
public enum VideoSize: String, Codable, CaseIterable, Sendable {
    case high
    case balanced
    case compact

    /// No camera format wider than this.
    public var maxFormatWidth: Int32 {
        switch self {
        case .high, .balanced: 1920
        case .compact: 1280
        }
    }

    /// Average bits a second asked of each stream's encoder; nil leaves the encoder its own.
    public var averageBitRate: Int? {
        switch self {
        case .high: nil
        case .balanced: 6_000_000
        case .compact: 2_500_000
        }
    }
}

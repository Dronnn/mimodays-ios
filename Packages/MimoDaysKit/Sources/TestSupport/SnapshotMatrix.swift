import SnapshotTesting
import SwiftUI
import Testing
import UIKit

public extension Tag {
    @Tag static var snapshot: Self
}

/// Device viewports used for screen snapshots, matching the design boards.
public enum SnapshotDevice: String, CaseIterable, Sendable {
    case iPhone
    case iPhoneCompact
    case iPad
    /// X01 and the other two-column iPad boards are drawn landscape.
    case iPadLandscape
    /// iPhone Duo's outer display: the status bar and tab bar on a strip at the trailing edge, no top inset.
    case duoOuter
    /// iPhone Duo open, landscape: regular width, the same trailing strip.
    case duoInner

    var size: CGSize {
        switch self {
        case .iPhone: CGSize(width: 402, height: 874)
        case .iPhoneCompact: CGSize(width: 375, height: 812)
        case .iPad: CGSize(width: 820, height: 1180)
        case .iPadLandscape: CGSize(width: 1180, height: 820)
        case .duoOuter: CGSize(width: 466, height: 678)
        case .duoInner: CGSize(width: 951, height: 669)
        }
    }

    var safeArea: UIEdgeInsets {
        switch self {
        case .iPhone: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        case .iPhoneCompact: UIEdgeInsets(top: 50, left: 0, bottom: 34, right: 0)
        case .iPad, .iPadLandscape: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
        case .duoOuter, .duoInner: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84)
        }
    }

    var isPad: Bool { self == .iPad || self == .iPadLandscape }
    var isRegular: Bool { isPad || self == .duoInner }
}

/// One rendering environment for a snapshot.
public struct SnapshotVariant: Sendable {
    public var device: SnapshotDevice
    public var style: UIUserInterfaceStyle
    public var contentSize: UIContentSizeCategory
    /// Right-to-left layout (Arabic, Hebrew) with the English strings.
    public var isRightToLeft: Bool
    /// iOS's Increase Contrast, or S04's Higher contrast.
    public var isHighContrast: Bool
    /// The app's language, e.g. "de"; nil is US English. Arabic and Hebrew also lay out right to left.
    public var language: String?

    public init(
        _ device: SnapshotDevice, _ style: UIUserInterfaceStyle, _ contentSize: UIContentSizeCategory = .large,
        rightToLeft: Bool = false, highContrast: Bool = false, language: String? = nil
    ) {
        self.device = device
        self.style = style
        self.contentSize = contentSize
        isRightToLeft = rightToLeft || language.map { Locale.Language(identifier: $0).characterDirection == .rightToLeft } == true
        isHighContrast = highContrast
        self.language = language
    }

    /// The longest words (German), right to left (Arabic) and CJK line breaking (Japanese), on iPhone.
    public static let languages: [SnapshotVariant] = ["de", "ar", "ja"].map { SnapshotVariant(.iPhone, .light, language: $0) }

    /// Every device in light and dark, iPhone at a large accessibility text size, and iPhone right-to-left.
    public static let standard: [SnapshotVariant] =
        [SnapshotDevice.iPhone, .iPhoneCompact, .iPad].flatMap { [SnapshotVariant($0, .light), SnapshotVariant($0, .dark)] }
        + [SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge), SnapshotVariant(.iPhone, .dark, .accessibilityExtraLarge)]
        + [SnapshotVariant(.iPhone, .light, rightToLeft: true)]

    var name: String {
        let styleName = style == .dark ? "dark" : "light"
        let sizeName = switch contentSize {
        case .large: "default"
        case .accessibilityExtraExtraExtraLarge: "AX5"
        default: "AX3"
        }
        if let language { return "\(device.rawValue)-\(styleName)-\(sizeName)-\(language)" }
        return "\(device.rawValue)-\(styleName)-\(sizeName)" + (isRightToLeft ? "-rtl" : "") + (isHighContrast ? "-hc" : "")
    }

    @MainActor var config: ViewImageConfig {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.preferredContentSizeCategory = contentSize
            traits.userInterfaceIdiom = device.isPad ? .pad : .phone
            traits.horizontalSizeClass = device.isRegular ? .regular : .compact
            traits.verticalSizeClass = .regular
            traits.layoutDirection = isRightToLeft ? .rightToLeft : .leftToRight
            traits.accessibilityContrast = isHighContrast ? .high : .normal
        }
        return ViewImageConfig(safeArea: device.safeArea, size: device.size, traits: traits)
    }
}

/// Snapshots a full-screen SwiftUI view in every variant.
/// Record references on the iPhone 18 Pro / iOS 27.2 simulator, the same one CI uses.
@MainActor
public func assertScreenSnapshots(
    of view: some View,
    variants: [SnapshotVariant] = SnapshotVariant.standard,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    for variant in variants {
        let controller = UIHostingController(
            rootView: view
                .environment(\.layoutDirection, variant.isRightToLeft ? .rightToLeft : .leftToRight)
                .environment(\.locale, variant.language.map(Locale.init(identifier:)) ?? snapshotLocale)
                .environment(\.calendar, snapshotCalendar)
                .environment(\.timeZone, snapshotCalendar.timeZone)
        )
        assertSnapshot(
            of: controller,
            // 1x keeps reference images small in git (Andrew, 2026-11-13); layout and colour regressions still show.
            as: .image(on: variant.config, precision: 0.995, perceptualPrecision: 0.98, traits: UITraitCollection(displayScale: 1)),
            named: variant.name,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}

/// Snapshots must not follow the Mac's region: US English, its Sunday-first week, UTC.
private let snapshotLocale = Locale(identifier: "en_US")
private let snapshotCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = snapshotLocale
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}()

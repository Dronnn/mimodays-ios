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

    var size: CGSize {
        switch self {
        case .iPhone: CGSize(width: 402, height: 874)
        case .iPhoneCompact: CGSize(width: 375, height: 812)
        case .iPad: CGSize(width: 820, height: 1180)
        }
    }

    var safeArea: UIEdgeInsets {
        switch self {
        case .iPhone: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        case .iPhoneCompact: UIEdgeInsets(top: 50, left: 0, bottom: 34, right: 0)
        case .iPad: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
        }
    }

    var isPad: Bool { self == .iPad }
}

/// One rendering environment for a snapshot.
public struct SnapshotVariant: Sendable {
    public var device: SnapshotDevice
    public var style: UIUserInterfaceStyle
    public var contentSize: UIContentSizeCategory

    public init(_ device: SnapshotDevice, _ style: UIUserInterfaceStyle, _ contentSize: UIContentSizeCategory = .large) {
        self.device = device
        self.style = style
        self.contentSize = contentSize
    }

    /// Every device in light and dark, plus iPhone at a large accessibility text size.
    public static let standard: [SnapshotVariant] =
        SnapshotDevice.allCases.flatMap { [SnapshotVariant($0, .light), SnapshotVariant($0, .dark)] }
        + [SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge), SnapshotVariant(.iPhone, .dark, .accessibilityExtraLarge)]

    var name: String {
        let styleName = style == .dark ? "dark" : "light"
        let sizeName = contentSize == .large ? "default" : "AX3"
        return "\(device.rawValue)-\(styleName)-\(sizeName)"
    }

    @MainActor var config: ViewImageConfig {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.preferredContentSizeCategory = contentSize
            traits.userInterfaceIdiom = device.isPad ? .pad : .phone
            traits.horizontalSizeClass = device.isPad ? .regular : .compact
            traits.verticalSizeClass = .regular
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
        let controller = UIHostingController(rootView: view)
        assertSnapshot(
            of: controller,
            as: .image(on: variant.config, precision: 0.995, perceptualPrecision: 0.98),
            named: variant.name,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}

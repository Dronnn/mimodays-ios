import Foundation

/// Process launch options that let UI tests put the app into a known state.
public struct LaunchConfiguration: Equatable, Sendable {
    /// Data the app starts with under UI tests.
    public enum Seed: String, CaseIterable, Sendable {
        case empty
        case populated
    }

    /// A surprise notification tap the app simulates at launch (UI tests for flow 02).
    public enum SurpriseTap: String, CaseIterable, Sendable {
        /// Tapped within the prompt's 15 minutes.
        case inTime
        /// Tapped after the prompt expired.
        case expired
    }

    public static let uiTestingArgument = "-ui-testing"
    public static let skipOnboardingArgument = "-skip-onboarding"
    public static let fakeCameraArgument = "-fake-camera"
    public static let seedArgument = "-seed"
    public static let permissionsArgument = "-permissions"
    public static let surpriseTapArgument = "-surprise-tap"

    public var isUITesting: Bool
    public var skipsOnboarding: Bool
    public var usesFakeCamera: Bool
    public var seed: Seed?
    /// Every permission starts in this state instead of asking the system (UI tests only).
    public var permissions: PermissionStatus?
    public var surpriseTap: SurpriseTap?

    public init(
        isUITesting: Bool, skipsOnboarding: Bool = false, usesFakeCamera: Bool = false,
        seed: Seed? = nil, permissions: PermissionStatus? = nil, surpriseTap: SurpriseTap? = nil
    ) {
        self.isUITesting = isUITesting
        self.skipsOnboarding = skipsOnboarding
        self.usesFakeCamera = usesFakeCamera
        self.seed = seed
        self.permissions = permissions
        self.surpriseTap = surpriseTap
    }

    public init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isUITesting = arguments.contains(Self.uiTestingArgument)
        skipsOnboarding = arguments.contains(Self.skipOnboardingArgument)
        usesFakeCamera = arguments.contains(Self.fakeCameraArgument)
        seed = Self.value(after: Self.seedArgument, in: arguments).flatMap(Seed.init(rawValue:))
        permissions = Self.value(after: Self.permissionsArgument, in: arguments).flatMap(PermissionStatus.init(rawValue:))
        surpriseTap = Self.value(after: Self.surpriseTapArgument, in: arguments).flatMap(SurpriseTap.init(rawValue:))
    }

    /// Launch arguments that reproduce this configuration, for `XCUIApplication.launchArguments`.
    public var arguments: [String] {
        var result: [String] = []
        if isUITesting { result.append(Self.uiTestingArgument) }
        if skipsOnboarding { result.append(Self.skipOnboardingArgument) }
        if usesFakeCamera { result.append(Self.fakeCameraArgument) }
        if let seed { result += [Self.seedArgument, seed.rawValue] }
        if let permissions { result += [Self.permissionsArgument, permissions.rawValue] }
        if let surpriseTap { result += [Self.surpriseTapArgument, surpriseTap.rawValue] }
        return result
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

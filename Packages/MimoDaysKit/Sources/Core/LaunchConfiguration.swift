import Foundation

/// Process launch options that let UI tests put the app into a known state.
public struct LaunchConfiguration: Equatable, Sendable {
    /// Data the app starts with under UI tests.
    public enum Seed: String, CaseIterable, Sendable {
        case empty
        case populated
    }

    public static let uiTestingArgument = "-ui-testing"
    public static let skipOnboardingArgument = "-skip-onboarding"
    public static let fakeCameraArgument = "-fake-camera"
    public static let seedArgument = "-seed"

    public var isUITesting: Bool
    public var skipsOnboarding: Bool
    public var usesFakeCamera: Bool
    public var seed: Seed?

    public init(isUITesting: Bool, skipsOnboarding: Bool = false, usesFakeCamera: Bool = false, seed: Seed? = nil) {
        self.isUITesting = isUITesting
        self.skipsOnboarding = skipsOnboarding
        self.usesFakeCamera = usesFakeCamera
        self.seed = seed
    }

    public init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isUITesting = arguments.contains(Self.uiTestingArgument)
        skipsOnboarding = arguments.contains(Self.skipOnboardingArgument)
        usesFakeCamera = arguments.contains(Self.fakeCameraArgument)
        seed = arguments.firstIndex(of: Self.seedArgument)
            .map { arguments.index(after: $0) }
            .flatMap { arguments.indices.contains($0) ? Seed(rawValue: arguments[$0]) : nil }
    }

    /// Launch arguments that reproduce this configuration, for `XCUIApplication.launchArguments`.
    public var arguments: [String] {
        var result: [String] = []
        if isUITesting { result.append(Self.uiTestingArgument) }
        if skipsOnboarding { result.append(Self.skipOnboardingArgument) }
        if usesFakeCamera { result.append(Self.fakeCameraArgument) }
        if let seed { result += [Self.seedArgument, seed.rawValue] }
        return result
    }
}

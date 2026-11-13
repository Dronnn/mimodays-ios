import Core
import Testing

struct LaunchConfigurationTests {
    @Test func defaultsToNormalLaunch() {
        let configuration = LaunchConfiguration(arguments: ["MimoDays"])
        #expect(configuration == LaunchConfiguration(isUITesting: false))
    }

    @Test func readsEveryFlag() {
        let configuration = LaunchConfiguration(arguments: [
            "MimoDays", "-ui-testing", "-skip-onboarding", "-fake-camera", "-seed", "populated", "-permissions", "denied",
        ])
        #expect(configuration == LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, usesFakeCamera: true, seed: .populated, permissions: .denied
        ))
    }

    @Test(arguments: [["-seed"], ["-seed", "unknown"]])
    func ignoresMissingOrUnknownSeed(_ tail: [String]) {
        #expect(LaunchConfiguration(arguments: ["MimoDays"] + tail).seed == nil)
    }

    @Test(arguments: [["-permissions"], ["-permissions", "maybe"]])
    func ignoresMissingOrUnknownPermissions(_ tail: [String]) {
        #expect(LaunchConfiguration(arguments: ["MimoDays"] + tail).permissions == nil)
    }

    @Test(arguments: LaunchConfiguration.Seed.allCases)
    func argumentsRoundTrip(seed: LaunchConfiguration.Seed) {
        let configuration = LaunchConfiguration(isUITesting: true, skipsOnboarding: true, seed: seed, permissions: .notDetermined)
        #expect(LaunchConfiguration(arguments: ["MimoDays"] + configuration.arguments) == configuration)
    }
}

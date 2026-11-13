import Core
import Testing

struct LaunchConfigurationTests {
    @Test func defaultsToNormalLaunch() {
        let configuration = LaunchConfiguration(arguments: ["MimoDays"])
        #expect(configuration == LaunchConfiguration(isUITesting: false))
    }

    @Test func readsEveryFlag() {
        let configuration = LaunchConfiguration(arguments: ["MimoDays", "-ui-testing", "-skip-onboarding", "-fake-camera", "-seed", "populated"])
        #expect(configuration == LaunchConfiguration(isUITesting: true, skipsOnboarding: true, usesFakeCamera: true, seed: .populated))
    }

    @Test(arguments: [["-seed"], ["-seed", "unknown"]])
    func ignoresMissingOrUnknownSeed(_ tail: [String]) {
        #expect(LaunchConfiguration(arguments: ["MimoDays"] + tail).seed == nil)
    }

    @Test(arguments: LaunchConfiguration.Seed.allCases)
    func argumentsRoundTrip(seed: LaunchConfiguration.Seed) {
        let configuration = LaunchConfiguration(isUITesting: true, skipsOnboarding: true, usesFakeCamera: false, seed: seed)
        #expect(LaunchConfiguration(arguments: ["MimoDays"] + configuration.arguments) == configuration)
    }
}

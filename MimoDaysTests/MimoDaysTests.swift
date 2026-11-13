import Foundation
import Testing

struct MimoDaysTests {
    @Test func appBundleIsConfigured() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["CFBundleDisplayName"] as? String == "MimoDays")
    }
}

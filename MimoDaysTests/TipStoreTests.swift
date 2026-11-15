@testable import AppFeature
import Core
import Foundation
import StoreKit
import StoreKitTest
import Testing

/// 14.9: the real StoreKit store against the local configuration.
/// `Product.purchase()` shows the system purchase sheet, which hosted unit tests can't answer, and the host app
/// already finishes every transaction it sees. Purchase outcomes are covered by `DonationsModelTests` with a fake
/// store and checked by hand on a device.
@MainActor
struct StoreKitTipStoreTests {
    @Test func loadsTheSixTipsWithTheirPrices() async throws {
        // The same file the MimoDays scheme runs with.
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "StoreKit/Tips.storekit")
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        let products = try await StoreKitTipStore().products()
        #expect(Set(products.map(\.id)) == Set(TipTier.allCases.map(\.productID)))
        #expect(products.first { $0.id == TipTier.generous.productID }?.displayPrice == "$19.99")
    }
}

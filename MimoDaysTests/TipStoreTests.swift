@testable import AppFeature
import Core
import Foundation
import StoreKit
import StoreKitTest
import Testing

/// 14.9: the real StoreKit store against the local configuration.
/// With dialogs off, the test session answers the purchase sheet itself: bought, failed, Ask to Buy. The thanks and
/// the screen's states are covered by `DonationsModelTests` with a fake store.
@MainActor
@Suite(.serialized)
struct StoreKitTipStoreTests {
    private func session() throws -> SKTestSession {
        // The same file the MimoDays scheme runs with.
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "StoreKit/Tips.storekit")
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    @Test func aTipIsBoughtAndFinished() async throws {
        let session = try session()
        #expect(try await StoreKitTipStore().purchase(productID: TipTier.small.productID) == .purchased)
        let transactions = session.allTransactions()
        #expect(transactions.count == 1 && transactions.allSatisfy { $0.productIdentifier == TipTier.small.productID })
        // Consumable and finished: nothing left unfinished for the next launch.
        var unfinished = 0
        for await _ in Transaction.unfinished { unfinished += 1 }
        #expect(unfinished == 0)
    }

    @Test func aFailedPurchaseThrows() async throws {
        let session = try session()
        try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        await #expect(throws: (any Error).self) { try await StoreKitTipStore().purchase(productID: TipTier.medium.productID) }
        try await session.setSimulatedError(nil, forAPI: .purchase)
    }

    @Test func askToBuyWaits() async throws {
        let session = try session()
        session.askToBuyEnabled = true
        #expect(try await StoreKitTipStore().purchase(productID: TipTier.large.productID) == .pending)
        session.askToBuyEnabled = false
    }

    /// Terms to accept first: no thanks until the purchase really completes.
    @Test func anInterruptedPurchaseIsNotThankedYet() async throws {
        let session = try session()
        session.interruptedPurchasesEnabled = true
        let outcome = try? await StoreKitTipStore().purchase(productID: TipTier.patron.productID)
        #expect(outcome != .purchased)
        session.interruptedPurchasesEnabled = false
    }

    @Test func anUnknownTipIsUnavailable() async throws {
        _ = try session()
        await #expect(throws: (any Error).self) { try await StoreKitTipStore().purchase(productID: "com.mrmaier.MimoDays.tip.none") }
    }

    @Test func loadsTheSixTipsWithTheirPrices() async throws {
        _ = try session()
        let products = try await StoreKitTipStore().products()
        #expect(Set(products.map(\.id)) == Set(TipTier.allCases.map(\.productID)))
        #expect(products.first { $0.id == TipTier.generous.productID }?.displayPrice == "$19.99")
    }
}

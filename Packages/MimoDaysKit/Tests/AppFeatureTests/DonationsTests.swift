@testable import AppFeature
import Core
import Foundation
import Testing
import TestSupport

/// 14.4-14.8: the tip jar's states with a fake store.
@MainActor
struct DonationsModelTests {
    private static let products = TipTier.allCases.map { TipProduct(id: $0.productID, displayPrice: "$\($0.rawValue.count).99") }

    @Test func pricesComeFromTheStore() async {
        let model = DonationsModel(store: FakeTipStore(products: Self.products))
        #expect(model.phase == .loading && model.tiers == TipTier.allCases)
        await model.load()
        #expect(model.phase == .ready)
        #expect(model.prices[.small] == "$5.99" && model.prices[.extraordinary] == "$13.99")
    }

    @Test func noProductsMeansNotAvailable() async {
        let model = DonationsModel(store: FakeTipStore(products: []))
        await model.load()
        #expect(model.phase == .unavailable && model.tiers.isEmpty)
    }

    @Test func aTipSaysThankYou() async {
        let store = FakeTipStore(products: Self.products, outcome: .purchased)
        let model = DonationsModel(store: store)
        await model.load()
        await model.buy(.medium)
        #expect(model.showsThankYou && model.notice == nil && model.purchasing == nil)
        #expect(await store.purchases == [TipTier.medium.productID])
    }

    @Test func cancellingChangesNothing() async {
        let model = DonationsModel(store: FakeTipStore(products: Self.products, outcome: .cancelled))
        await model.load()
        await model.buy(.large)
        #expect(!model.showsThankYou && model.notice == nil)
    }

    @Test func askToBuyWaitsForApproval() async {
        let model = DonationsModel(store: FakeTipStore(products: Self.products, outcome: .pending))
        await model.load()
        await model.buy(.patron)
        #expect(!model.showsThankYou && model.notice == .pending)
    }

    /// rev-app 13: approved while Donations was closed: thanked on the next visit, once.
    @Test func aTipApprovedLaterIsThankedForOnTheNextVisit() async throws {
        let defaults = try #require(UserDefaults(suiteName: "Tips-\(UUID().uuidString)"))
        TipsApprovedLater.record(in: defaults)
        let model = DonationsModel(store: FakeTipStore(products: Self.products), defaults: defaults)
        await model.load()
        #expect(model.showsThankYou)
        let again = DonationsModel(store: FakeTipStore(products: Self.products), defaults: defaults)
        await again.load()
        #expect(!again.showsThankYou)
    }

    /// rev-app 13: approved while Donations is open, even after another tip cleared the waiting note.
    @Test func aTipApprovedWhileOpenIsThankedFor() async throws {
        let defaults = try #require(UserDefaults(suiteName: "Tips-\(UUID().uuidString)"))
        let model = DonationsModel(store: FakeTipStore(products: Self.products, outcome: .cancelled), defaults: defaults)
        await model.load()
        model.finishedLater()
        #expect(!model.showsThankYou)
        TipsApprovedLater.record(in: defaults)
        model.finishedLater()
        #expect(model.showsThankYou)
    }

    @Test func productIDsMatchTheTiers() {
        #expect(TipTier.allCases.map(\.productID) == [
            "com.mrmaier.MimoDays.tip.small", "com.mrmaier.MimoDays.tip.medium", "com.mrmaier.MimoDays.tip.large",
            "com.mrmaier.MimoDays.tip.generous", "com.mrmaier.MimoDays.tip.patron", "com.mrmaier.MimoDays.tip.extraordinary",
        ])
        #expect(TipTier(productID: "com.mrmaier.MimoDays.tip.patron") == .patron)
        #expect(TipTier(productID: "com.other.tip.patron") == nil)
    }
}

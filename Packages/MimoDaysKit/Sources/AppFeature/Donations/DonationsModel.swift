import Core
import Foundation
import Observation
import SwiftUI

/// D01-D04: loads the tips' prices and buys one. Nothing in the app depends on whether anyone tips.
@MainActor
@Observable
final class DonationsModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// D04: no products (offline, region, or not set up yet).
        case unavailable
    }

    enum Notice: Equatable {
        /// The purchase failed; nothing was bought.
        case failed
        /// Ask to Buy: it goes through once approved.
        case pending
        /// The App Store answered, but the purchase couldn't be verified: it may have been charged.
        case unconfirmed
    }

    private(set) var phase = Phase.loading
    /// Localized prices from the App Store, never written in the app.
    private(set) var prices: [TipTier: String] = [:]
    /// D02: the tip whose payment sheet is up.
    private(set) var purchasing: TipTier?
    private(set) var notice: Notice?
    /// D03.
    var showsThankYou = false

    private let store: any TipStore
    private let defaults: UserDefaults

    init(store: any TipStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    /// The tiers the App Store offers, in their order.
    var tiers: [TipTier] {
        phase == .loading ? TipTier.allCases : TipTier.allCases.filter { prices[$0] != nil }
    }

    func load() async {
        phase = .loading
        do {
            let products = try await store.products()
            prices = Dictionary(
                products.compactMap { product in TipTier(productID: product.id).map { ($0, product.displayPrice) } },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            prices = [:]
        }
        phase = prices.isEmpty ? .unavailable : .ready
        thankForTipsApprovedLater()
    }

    /// A tip that was waiting for approval went through, while Donations is open.
    func finishedLater() {
        thankForTipsApprovedLater()
    }

    /// D03 for tips approved while Donations was closed or on another tip (rev-app 13), once.
    private func thankForTipsApprovedLater() {
        guard TipsApprovedLater.take(from: defaults) else { return }
        if notice == .pending { notice = nil }
        showsThankYou = true
    }

    func buy(_ tier: TipTier) async {
        guard phase == .ready, purchasing == nil else { return }
        purchasing = tier
        notice = nil
        defer { purchasing = nil }
        do {
            switch try await store.purchase(productID: tier.productID) {
            case .purchased: showsThankYou = true
            case .pending: notice = .pending
            case .cancelled: break
            }
        } catch StoreKitTipStore.Failure.unverified {
            notice = .unconfirmed
        } catch {
            notice = .failed
        }
    }
}

/// UI tests and previews: US prices, every tip goes through.
final class SampleTipStore: TipStore {
    static let prices: [TipTier: String] = [
        .small: "$2.99", .medium: "$4.99", .large: "$7.99", .generous: "$19.99", .patron: "$49.99", .extraordinary: "$99.99",
    ]

    func products() async throws -> [TipProduct] {
        TipTier.allCases.map { TipProduct(id: $0.productID, displayPrice: Self.prices[$0] ?? "") }
    }

    func purchase(productID _: String) async throws -> PurchaseOutcome { .purchased }
}

extension EnvironmentValues {
    /// D01's store; nil in previews.
    @Entry var tipStore: (any TipStore)?
}

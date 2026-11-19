import Core
import Foundation
import os
import StoreKit

/// The six tips, as App Store Connect and the StoreKit configuration know them.
enum TipTier: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large
    case generous
    case patron
    case extraordinary

    static let productIDPrefix = "com.mrmaier.MimoDays.tip."

    var id: String { productID }
    var productID: String { Self.productIDPrefix + rawValue }

    init?(productID: String) {
        guard productID.hasPrefix(Self.productIDPrefix) else { return nil }
        self.init(rawValue: String(productID.dropFirst(Self.productIDPrefix.count)))
    }
}

/// StoreKit 2 behind `TipStore`: consumable tips, finished as soon as they're verified.
final class StoreKitTipStore: TipStore {
    enum Failure: Error {
        case unavailable
        case unverified
    }

    private static let logger = Logger(subsystem: "MimoDays", category: "Donations")

    func products() async throws -> [TipProduct] {
        let products = try await Product.products(for: TipTier.allCases.map(\.productID))
        guard !products.isEmpty else { throw Failure.unavailable }
        return products.map { TipProduct(id: $0.id, displayPrice: $0.displayPrice) }
    }

    func purchase(productID: String) async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [productID]).first else { throw Failure.unavailable }
        switch try await product.purchase() {
        case let .success(result):
            guard case let .verified(transaction) = result else { throw Failure.unverified }
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Posted on the main actor when a tip arrives through `listenForTransactions`.
    static let finishedLater = Notification.Name("MimoDaysTipFinishedLater")

    /// Tips approved later (Ask to Buy) or bought on another device arrive here; each is finished once verified.
    /// Runs for the app's lifetime.
    static func listenForTransactions() -> Task<Void, Never> {
        Task.detached(priority: .background) {
            for await result in Transaction.updates {
                guard case let .verified(transaction) = result else {
                    logger.error("A tip transaction failed verification")
                    continue
                }
                await transaction.finish()
                await MainActor.run { NotificationCenter.default.post(name: finishedLater, object: nil) }
            }
        }
    }
}

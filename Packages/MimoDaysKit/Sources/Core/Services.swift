import Foundation

// System services behind protocols so features can be tested with fakes (TestSupport).
// These are first shapes; each one is finalised in the plan step that implements it.

// MARK: Clock

public protocol DateProvider: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProvider {
    public init() {}
    public func now() -> Date { Date() }
}

// MARK: Notifications (5.1-5.2)

public struct SurpriseNotification: Equatable, Identifiable, Sendable {
    /// Key in the notification's `userInfo` holding the prompt's UUID string.
    public static let promptIDKey = "promptID"

    /// The prompt's UUID string, also the notification request identifier.
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String

    public init(id: String, fireDate: Date, title: String = "", body: String = "") {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

public protocol NotificationScheduler: Sendable {
    func pending() async -> [SurpriseNotification]
    func schedule(_ notification: SurpriseNotification) async throws
    func cancel(ids: [String]) async
}

// MARK: Location (7.4)

public struct GeoPoint: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
    }
}

public protocol LocationProvider: Sendable {
    /// One-shot fix for a moment's place.
    func currentLocation() async throws -> GeoPoint
}

// MARK: Photos (12.x)

public protocol PhotoLibrary: Sendable {
    func saveImage(at url: URL) async throws
    func saveVideo(at url: URL) async throws
}

// MARK: StoreKit tips (14.x)

public struct TipProduct: Equatable, Identifiable, Sendable {
    public var id: String
    public var displayPrice: String

    public init(id: String, displayPrice: String) {
        self.id = id
        self.displayPrice = displayPrice
    }
}

public enum PurchaseOutcome: Equatable, Sendable {
    case purchased
    case cancelled
    case pending
}

public protocol TipStore: Sendable {
    func products() async throws -> [TipProduct]
    func purchase(productID: String) async throws -> PurchaseOutcome
}

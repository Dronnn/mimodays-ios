import Core
import Foundation
import Synchronization

public enum FakeServiceError: Error, Equatable, Sendable {
    case unavailable
}

/// Clock that only moves when a test says so.
public final class TestDateProvider: DateProvider {
    private let current: Mutex<Date>

    public init(_ date: Date = Date(timeIntervalSince1970: 1_794_355_200)) { // 2026-11-11 00:00 UTC
        current = Mutex(date)
    }

    public func now() -> Date { current.withLock { $0 } }

    public func set(_ date: Date) { current.withLock { $0 = date } }

    public func advance(by interval: TimeInterval) { current.withLock { $0 += interval } }
}

/// Deterministic generator (SplitMix64) for seeded scheduler tests.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public actor FakePermissionService: PermissionService {
    public var statuses: [Permission: PermissionStatus]
    /// What a request returns; defaults to granted.
    public var requestResults: [Permission: PermissionStatus]
    public private(set) var requested: [Permission] = []

    public init(statuses: [Permission: PermissionStatus] = [:], requestResults: [Permission: PermissionStatus] = [:]) {
        self.statuses = statuses
        self.requestResults = requestResults
    }

    public func status(of permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    public func request(_ permission: Permission) -> PermissionStatus {
        requested.append(permission)
        let result = requestResults[permission] ?? .granted
        statuses[permission] = result
        return result
    }
}

public actor FakeNotificationScheduler: NotificationScheduler {
    public private(set) var scheduled: [String: SurpriseNotification] = [:]
    public var scheduleError: FakeServiceError?

    public init() {}

    public func pending() -> [SurpriseNotification] {
        scheduled.values.sorted { $0.fireDate < $1.fireDate }
    }

    public func schedule(_ notification: SurpriseNotification) throws {
        if let scheduleError { throw scheduleError }
        scheduled[notification.id] = notification
    }

    public func cancel(ids: [String]) {
        ids.forEach { scheduled[$0] = nil }
    }
}

public actor FakeLocationProvider: LocationProvider {
    /// Nil makes `currentLocation()` throw.
    public var location: GeoPoint?

    public init(location: GeoPoint? = GeoPoint(latitude: 37.8044, longitude: -122.2590, horizontalAccuracy: 50)) {
        self.location = location
    }

    public func currentLocation() throws -> GeoPoint {
        guard let location else { throw FakeServiceError.unavailable }
        return location
    }
}

public actor FakePhotoLibrary: PhotoLibrary {
    public private(set) var savedImages: [URL] = []
    public private(set) var savedVideos: [URL] = []

    public init() {}

    public func saveImage(at url: URL) { savedImages.append(url) }

    public func saveVideo(at url: URL) { savedVideos.append(url) }
}

public actor FakeTipStore: TipStore {
    public var availableProducts: [TipProduct]
    public var outcome: PurchaseOutcome
    public private(set) var purchases: [String] = []

    public init(products: [TipProduct] = [], outcome: PurchaseOutcome = .purchased) {
        availableProducts = products
        self.outcome = outcome
    }

    public func products() throws -> [TipProduct] {
        guard !availableProducts.isEmpty else { throw FakeServiceError.unavailable }
        return availableProducts
    }

    public func purchase(productID: String) -> PurchaseOutcome {
        purchases.append(productID)
        return outcome
    }
}

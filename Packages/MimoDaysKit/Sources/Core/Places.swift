import CoreLocation
import MapKit

/// A place to pick in C11: nearby or from a search.
public struct PlaceSuggestion: Equatable, Sendable, Identifiable {
    public var name: String
    /// Under the name in search results: the city, or the address.
    public var detail: String?
    public var latitude: Double
    public var longitude: Double

    public var id: String { "\(name)|\(latitude)|\(longitude)" }

    public init(name: String, detail: String? = nil, latitude: Double, longitude: Double) {
        self.name = name
        self.detail = detail
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Apple's MapKit services for C11 (Andrew, 2026-11-13). Only the point or the typed text goes to Apple.
public protocol PlaceLookup: Sendable {
    /// The city at `point`, in the person's language.
    func city(at point: GeoPoint) async -> String?
    /// Points of interest around `point`, closest first.
    func nearby(_ point: GeoPoint) async -> [PlaceSuggestion]
    func search(_ text: String, near point: GeoPoint?) async -> [PlaceSuggestion]
}

public struct MapKitPlaceLookup: PlaceLookup {
    /// "Nearby" means a short walk.
    static let nearbyRadius: CLLocationDistance = 300

    public init() {}

    public func city(at point: GeoPoint) async -> String? {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            return try? await request.mapItems.first?.addressRepresentations?.cityName
        }
        return try? await CLGeocoder().reverseGeocodeLocation(location).first?.locality
    }

    public func nearby(_ point: GeoPoint) async -> [PlaceSuggestion] {
        let request = MKLocalPointsOfInterestRequest(center: point.coordinate, radius: Self.nearbyRadius)
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        let here = CLLocation(latitude: point.latitude, longitude: point.longitude)
        return items.compactMap(PlaceSuggestion.init).sorted {
            here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < here.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
    }

    public func search(_ text: String, near point: GeoPoint?) async -> [PlaceSuggestion] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let point {
            request.region = MKCoordinateRegion(center: point.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        return items.compactMap(PlaceSuggestion.init)
    }
}

extension PlaceSuggestion {
    init?(_ item: MKMapItem) {
        guard let name = item.name, !name.isEmpty else { return nil }
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
            detail = item.addressRepresentations?.cityWithContext
        } else {
            coordinate = item.placemark.coordinate
            detail = item.placemark.locality
        }
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        if detail == name { detail = nil }
    }
}

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// One fix when a moment needs it; never tracked in the background (doc 01 §Map).
public struct SystemLocationProvider: LocationProvider {
    /// Long enough for a first fix indoors; a moment saves fine without one.
    static let timeout: Duration = .seconds(15)

    public init() {}

    public func currentLocation() async throws -> GeoPoint {
        try await withThrowingTaskGroup(of: GeoPoint.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location, location.horizontalAccuracy >= 0 {
                        return GeoPoint(
                            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                            horizontalAccuracy: location.horizontalAccuracy
                        )
                    }
                }
                throw CLError(.locationUnknown)
            }
            group.addTask {
                try await Task.sleep(for: Self.timeout)
                throw CLError(.locationUnknown)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CLError(.locationUnknown) }
            return first
        }
    }
}

/// UI tests and previews: Yerevan, with a few places around it.
public struct SimulatedLocationProvider: LocationProvider {
    public init() {}

    public func currentLocation() async throws -> GeoPoint {
        GeoPoint(latitude: 40.18111, longitude: 44.51361, horizontalAccuracy: 30)
    }
}

public struct SimulatedPlaceLookup: PlaceLookup {
    private static let places = [
        PlaceSuggestion(name: "Cascade Complex", detail: "Yerevan", latitude: 40.19087, longitude: 44.51521),
        PlaceSuggestion(name: "Republic Square", detail: "Yerevan", latitude: 40.17765, longitude: 44.51262),
        PlaceSuggestion(name: "Vernissage Market", detail: "Yerevan", latitude: 40.17689, longitude: 44.51956),
        PlaceSuggestion(name: "Lake Sevan", detail: "Gegharkunik", latitude: 40.55920, longitude: 45.00800),
    ]

    public init() {}

    public func city(at _: GeoPoint) async -> String? { "Yerevan" }

    public func nearby(_: GeoPoint) async -> [PlaceSuggestion] { Array(Self.places.prefix(2)) }

    public func search(_ text: String, near _: GeoPoint?) async -> [PlaceSuggestion] {
        Self.places.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }
}

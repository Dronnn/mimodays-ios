import Core
import Foundation
import Persistence
import SwiftData

/// C11: where the moment happened, as it will be saved.
struct ReviewPlace: Codable, Equatable {
    /// "Yerevan", "Cascade Complex"; nil when the city couldn't be looked up.
    var label: String?
    var latitude: Double?
    var longitude: Double?
    var precision: LocationPrecision
    var source: LocationSource

    /// This iPhone's position at city level (Andrew, 2026-11-13): the city's name and the fix rounded to about 1 km.
    /// The exact fix is never kept.
    static func current(city: String?, at fix: GeoPoint) -> ReviewPlace {
        ReviewPlace(
            label: city, latitude: (fix.latitude * 100).rounded() / 100, longitude: (fix.longitude * 100).rounded() / 100,
            precision: .city, source: .gps
        )
    }

    /// A place picked by name, nearby or from a search: where that place is.
    static func picked(_ suggestion: PlaceSuggestion) -> ReviewPlace {
        ReviewPlace(label: suggestion.name, latitude: suggestion.latitude, longitude: suggestion.longitude, precision: .exact, source: .manual)
    }
}

/// A place earlier moments were saved with ("Used 4 times").
struct RecentPlace: Equatable, Identifiable {
    var place: ReviewPlace
    var uses: Int

    var id: String { place.label ?? "" }

    /// Named places from saved moments, the most used first, then the latest.
    @MainActor
    static func load(from context: ModelContext, limit: Int = 3) -> [RecentPlace] {
        let descriptor = FetchDescriptor<MomentLocation>(predicate: #Predicate { $0.placeLabel != nil })
        guard let locations = try? context.fetch(descriptor) else { return [] }
        var byLabel: [String: (place: ReviewPlace, uses: Int, latest: Date)] = [:]
        for location in locations {
            guard let label = location.placeLabel else { continue }
            let date = location.moment?.capturedAt ?? .distantPast
            let place = ReviewPlace(
                label: label, latitude: location.latitude, longitude: location.longitude,
                precision: location.precision, source: location.source
            )
            if let known = byLabel[label] {
                byLabel[label] = (date > known.latest ? place : known.place, known.uses + 1, max(date, known.latest))
            } else {
                byLabel[label] = (place, 1, date)
            }
        }
        return byLabel.values
            .sorted { $0.uses != $1.uses ? $0.uses > $1.uses : $0.latest > $1.latest }
            .prefix(limit)
            .map { RecentPlace(place: $0.place, uses: $0.uses) }
    }
}

/// C11: one location fix, Apple's lookups, and places used before.
struct PlaceServices {
    var location: any LocationProvider
    var lookup: any PlaceLookup
    var recents: @MainActor () -> [RecentPlace]

    @MainActor static var simulated: PlaceServices {
        PlaceServices(location: SimulatedLocationProvider(), lookup: SimulatedPlaceLookup(), recents: { [] })
    }
}

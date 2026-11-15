import Foundation
import Persistence

/// S06: what a new movie and an export start with. Each movie and export can still change them.
struct MovieDefaults: Codable, Equatable, Sendable {
    var aspectRatio = MovieAspectRatio.portrait9x16
    /// Quick, Short or Full; a custom length is chosen per movie.
    var length = MovieLength.quick
    var showsDates = true
    var showsPlaces = true
    var transition = MovieTransition.cut
    var resolution = MovieResolution.p1080
    /// The exact place in exported movies and moments; off keeps it out of the files.
    var exactPlaceInFiles = false

    static let lengths: [MovieLength] = [.quick, .short, .full]

    init() {}

    /// Settings saved by an earlier version lack the newer keys; those keep their defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aspectRatio = try container.decodeIfPresent(MovieAspectRatio.self, forKey: .aspectRatio) ?? aspectRatio
        length = try container.decodeIfPresent(MovieLength.self, forKey: .length) ?? length
        showsDates = try container.decodeIfPresent(Bool.self, forKey: .showsDates) ?? showsDates
        showsPlaces = try container.decodeIfPresent(Bool.self, forKey: .showsPlaces) ?? showsPlaces
        transition = try container.decodeIfPresent(MovieTransition.self, forKey: .transition) ?? transition
        resolution = try container.decodeIfPresent(MovieResolution.self, forKey: .resolution) ?? resolution
        exactPlaceInFiles = try container.decodeIfPresent(Bool.self, forKey: .exactPlaceInFiles) ?? exactPlaceInFiles
    }
}

typealias MoviePreferences = DevicePreference<MovieDefaults>

extension DevicePreference<MovieDefaults> {
    static func movies(_ defaults: UserDefaults?) -> MoviePreferences {
        MoviePreferences(key: "movieDefaults", defaults: defaults, initial: MovieDefaults())
    }
}

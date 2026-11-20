@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 13.5 (S06): new movies and exports start with what Settings says.
@MainActor
struct MovieDefaultsTests {
    private let container = try! TestStore.container()
    private let store = try! MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MovieDefaults-\(UUID().uuidString)"))

    private var context: ModelContext { container.mainContext }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }

    private var changed: MovieDefaults {
        var defaults = MovieDefaults()
        defaults.aspectRatio = .landscape16x9
        defaults.length = .short
        defaults.showsDates = false
        defaults.showsPlaces = false
        defaults.transition = .fade
        defaults.resolution = .p720
        defaults.exactPlaceInFiles = true
        return defaults
    }

    @Test func aNewMovieStartsWithTheDefaults() throws {
        let moments = (0..<3).map { index in
            Moment(
                captured: CaptureTime(instant: Date(timeIntervalSince1970: 1_794_355_200 + Double(index) * 3600), timeZone: .gmt),
                origin: .manual, mediaType: .photo, createdAt: .now
            )
        }
        moments.forEach(context.insert)
        let model = NewMovieModel(library: library, defaults: changed)
        #expect(model.aspectRatio == .landscape16x9)
        #expect(model.length == .short)
        let project = try MovieStore(context: context, store: store, now: { .now }).create(
            title: "November", source: MovieSourceRule(kind: .selection), length: model.length, aspectRatio: model.aspectRatio, fit: .fill,
            momentIDs: moments.map(\.id), defaults: changed
        )
        #expect(!project.showsDates && !project.showsPlaces)
        #expect(project.clips.count == 3 && project.clips.allSatisfy { $0.transition == .fade })
    }

    @Test func defaultsAreKeptAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "MovieDefaultsTests"))
        defaults.removePersistentDomain(forName: "MovieDefaultsTests")
        MoviePreferences.movies(defaults).value = changed
        #expect(MoviePreferences.movies(defaults).value == changed)
    }

    @Test func momentExportsStartWithTheExactPlaceSetting() {
        #expect(MomentExportModel(ids: [], library: library, exactPlace: true).options.exactPlace)
        #expect(!MomentExportModel(ids: [], library: library).options.exactPlace)
    }
}

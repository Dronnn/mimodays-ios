import Core
import DesignSystem
import Foundation
import Observation
import Persistence
import SwiftUI

public enum MainTab: String, CaseIterable, Hashable, Sendable {
    case today
    case memories
    case map
    case movies

    var title: LocalizedStringResource {
        switch self {
        case .today: LocalizedStringResource("Today", bundle: .atURL(Bundle.module.bundleURL))
        case .memories: LocalizedStringResource("Memories", bundle: .atURL(Bundle.module.bundleURL))
        case .map: LocalizedStringResource("Map", bundle: .atURL(Bundle.module.bundleURL))
        case .movies: LocalizedStringResource("Movies", bundle: .atURL(Bundle.module.bundleURL))
        }
    }

    var icon: Icon {
        switch self {
        case .today: .tabToday
        case .memories: .tabMemories
        case .map: .tabMap
        case .movies: .tabMovies
        }
    }
}

/// Where the app can be sent from outside: a notification, a link, or a UI test.
public enum Route: Equatable, Sendable {
    case tab(MainTab)
    case settings
    /// Opens the camera. `promptID` is set when answering a surprise.
    case capture(promptID: UUID?)
    /// P8.8 "Capture this again": a plain camera whose moment links to this one.
    case captureAgain(UUID)
    /// Starts a movie (F02) on Movies, from a source chosen elsewhere when there is one (a place, a selection).
    case newMovie(MovieSourceRule?)
}

/// A screen pushed on Movies (F06, F11, F15).
enum MovieRoute: Hashable {
    /// F06-F09.
    case editor(UUID)
    /// F15.
    case movie(UUID)
    /// F11-F14.
    case export(UUID)
}

/// A movie wizard to show, maybe with its source already chosen.
public struct NewMovieRequest: Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var source: MovieSourceRule?
}

/// What the camera was opened for.
public struct CaptureRequest: Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var promptID: UUID?
    /// P8.8: the moment this captures again.
    public var repeatOf: UUID?

    public var isSurprise: Bool { promptID != nil }

    public static func == (lhs: CaptureRequest, rhs: CaptureRequest) -> Bool { lhs.promptID == rhs.promptID && lhs.repeatOf == rhs.repeatOf }
}

/// Navigation state for the whole app. Views read it; routes come in through `open(_:)`.
@MainActor
@Observable
public final class AppRouter {
    public var selectedTab: MainTab
    public var isSettingsPresented = false
    /// The camera, then Review. A route that comes while it's up waits until it closes (Andrew, 2026-11-19): a Review
    /// left behind would go on saving and writing while its draft opened again.
    public var capture: CaptureRequest? {
        didSet {
            guard capture == nil else { return }
            // A surprise tapped meanwhile comes first, if it can still be answered (P2.0).
            if let surprise = heldSurprise {
                heldSurprise = nil
                if isAnswerable(surprise) {
                    held = nil
                    open(.capture(promptID: surprise))
                    return
                }
            }
            guard let held else { return }
            self.held = nil
            open(held)
        }
    }
    /// A route waiting for the camera to close; a later one takes its place.
    var held: Route?
    /// A surprise tapped while the camera was up; the latest one wins.
    var heldSurprise: UUID?
    /// Opens a held surprise's prompt; false when it can't be answered any more (expired, caught, gone).
    var isAnswerable: (UUID) -> Bool = { _ in false }
    public var newMovie: NewMovieRequest?
    /// What's pushed on Movies.
    var moviesPath: [MovieRoute] = []
    /// What's pushed on Today (the camera's last capture opens there).
    var todayPath = NavigationPath()

    public init(selectedTab: MainTab = .today) {
        self.selectedTab = selectedTab
    }

    public func open(_ route: Route) {
        // Another camera over the open one would start over its capture; it stays as it is.
        if capture != nil {
            if case .capture = route { return }
            if case .captureAgain = route { return }
            held = route
            return
        }
        switch route {
        case let .tab(tab):
            dismissAll()
            selectedTab = tab
        case .settings:
            isSettingsPresented = true
        case let .newMovie(source):
            dismissAll()
            selectedTab = .movies
            moviesPath = []
            newMovie = NewMovieRequest(source: source)
        case let .capture(promptID):
            // A surprise wins over whatever is on screen; Capture lives on Today.
            isSettingsPresented = false
            newMovie = nil
            selectedTab = .today
            capture = CaptureRequest(promptID: promptID)
        case let .captureAgain(source):
            isSettingsPresented = false
            newMovie = nil
            selectedTab = .today
            capture = CaptureRequest(repeatOf: source)
        }
    }

    public func dismissAll() {
        isSettingsPresented = false
        capture = nil
        newMovie = nil
    }

    // MARK: Parsing

    public static let urlScheme = "mimodays"
    /// Key in a surprise notification's `userInfo`.
    public static let promptIDKey = SurpriseNotification.promptIDKey

    /// `mimodays://capture?prompt=<uuid>`, `mimodays://settings`, `mimodays://today` (and the other tabs).
    public static func route(from url: URL) -> Route? {
        guard url.scheme == urlScheme, let host = url.host() else { return nil }
        switch host {
        case "capture":
            let prompt = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "prompt" }?.value
            return .capture(promptID: prompt.flatMap(UUID.init(uuidString:)))
        case "settings":
            return .settings
        default:
            return MainTab(rawValue: host).map(Route.tab)
        }
    }

    /// A surprise notification opens the camera directly (UX decision 3).
    public nonisolated static func route(fromNotification userInfo: [AnyHashable: Any]) -> Route? {
        guard let value = userInfo[SurpriseNotification.promptIDKey] as? String, let id = UUID(uuidString: value) else { return nil }
        return .capture(promptID: id)
    }
}

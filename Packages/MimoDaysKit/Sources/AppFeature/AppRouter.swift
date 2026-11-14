import Core
import DesignSystem
import Foundation
import Observation
import Persistence

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
    /// Starts a movie (F02) on Movies, from a source chosen elsewhere when there is one (a place, a selection).
    case newMovie(MovieSourceRule?)
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

    public var isSurprise: Bool { promptID != nil }

    public static func == (lhs: CaptureRequest, rhs: CaptureRequest) -> Bool { lhs.promptID == rhs.promptID }
}

/// Navigation state for the whole app. Views read it; routes come in through `open(_:)`.
@MainActor
@Observable
public final class AppRouter {
    public var selectedTab: MainTab
    public var isSettingsPresented = false
    public var capture: CaptureRequest?
    public var newMovie: NewMovieRequest?

    public init(selectedTab: MainTab = .today) {
        self.selectedTab = selectedTab
    }

    public func open(_ route: Route) {
        switch route {
        case let .tab(tab):
            dismissAll()
            selectedTab = tab
        case .settings:
            capture = nil
            isSettingsPresented = true
        case let .newMovie(source):
            dismissAll()
            selectedTab = .movies
            newMovie = NewMovieRequest(source: source)
        case let .capture(promptID):
            // A surprise wins over whatever is on screen; Capture lives on Today.
            isSettingsPresented = false
            newMovie = nil
            selectedTab = .today
            capture = CaptureRequest(promptID: promptID)
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

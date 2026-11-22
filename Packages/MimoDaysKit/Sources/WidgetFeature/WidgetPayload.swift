import Foundation

/// P8.2: what the app hands its widgets. Only what they show: no captions, notes, tags or moods. Pictures only with
/// Show photos in widgets on, and nothing at all under App Lock.
public struct WidgetPayload: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case photo
        case video
        case livePhoto
        /// A moment in words: a paper tile, never its text.
        case text
    }

    public struct Memory: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        /// The day it was taken, yyyymmdd.
        public var day: Int
        public var place: String?
        public var kind: Kind
        /// A small picture's file name on the shelf; nil with photos off and for words.
        public var image: String?

        public init(id: UUID, day: Int, place: String?, kind: Kind, image: String? = nil) {
            self.id = id
            self.day = day
            self.place = place
            self.kind = kind
            self.image = image
        }
    }

    /// On this day for one day: the nearest earlier year with moments on its month and day.
    public struct Day: Codable, Equatable, Sendable {
        /// The day it shows on, yyyymmdd.
        public var today: Int
        /// How many moments that year has on the day.
        public var count: Int
        public var cover: Memory

        public init(today: Int, count: Int, cover: Memory) {
            self.today = today
            self.count = count
            self.cover = cover
        }
    }

    public var isLocked: Bool
    /// Show photos in widgets: pictures, and a paper tile for words.
    public var showsPhotos: Bool
    /// The language MimoDays shows, so the widgets speak it too.
    public var language: String
    /// The days On this day was worked out for, yyyymmdd; a day outside them shows the plain tile.
    public var firstDay: Int
    public var lastDay: Int
    public var onThisDay: [Day]
    /// Random memory's pool.
    public var random: [Memory]

    public init(
        isLocked: Bool = false, showsPhotos: Bool = false, language: String, firstDay: Int = 0, lastDay: Int = 0, onThisDay: [Day] = [], random: [Memory] = []
    ) {
        self.isLocked = isLocked
        self.showsPhotos = showsPhotos
        self.language = language
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.onThisDay = onThisDay
        self.random = random
    }

    /// App Lock on: only MimoDays and Open MimoDays.
    public static func locked(language: String) -> WidgetPayload {
        WidgetPayload(isLocked: true, language: language)
    }

    /// Every picture it names.
    public var images: Set<String> {
        Set((onThisDay.map(\.cover) + random).compactMap(\.image))
    }
}

/// Where a widget's tap leads (`mimodays://…`, read by the app's router).
public enum WidgetLink {
    public static func memory(_ id: UUID) -> URL { URL(string: "mimodays://memory/\(id.uuidString)")! }
    public static let onThisDay = URL(string: "mimodays://onthisday")!
    public static let app = URL(string: "mimodays://today")!
}

/// The widgets' words for the extension's own configuration (gallery names, the control's name).
public enum WidgetText {
    public static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }

    public static var onThisDay: LocalizedStringResource { resource("On this day") }
    public static var randomMemory: LocalizedStringResource { resource("Random memory") }
    public static var onThisDayDescription: LocalizedStringResource { resource("Moments from this date in past years.") }
    public static var randomMemoryDescription: LocalizedStringResource { resource("One memory at a time; Another shows a different one.") }
    public static var camera: LocalizedStringResource { resource("MimoDays Camera") }
    public static var another: LocalizedStringResource { resource("Another") }
}

import Foundation

/// The six educational pages, OB-01 to OB-06 (doc 01 §5), in order.
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case surprise
    case dualCamera
    case voice
    case movie
    case privacy

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .welcome: LocalizedStringResource("Your life, in little pieces.", bundle: .atURL(Bundle.module.bundleURL))
        case .surprise: LocalizedStringResource("A little surprise, every day.", bundle: .atURL(Bundle.module.bundleURL))
        case .dualCamera: LocalizedStringResource("You and the world around you.", bundle: .atURL(Bundle.module.bundleURL))
        case .voice: LocalizedStringResource("Give your moment a voice.", bundle: .atURL(Bundle.module.bundleURL))
        case .movie: LocalizedStringResource("One day, it becomes a movie.", bundle: .atURL(Bundle.module.bundleURL))
        case .privacy: LocalizedStringResource("Your moments. Your memories.", bundle: .atURL(Bundle.module.bundleURL))
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .welcome:
            LocalizedStringResource(
                "We take photos of birthdays and big adventures. But most of life happens on ordinary days. MimoDays helps you remember those, too.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .surprise:
            LocalizedStringResource(
                "At a random moment, MimoDays may invite you to capture what is happening right now. Busy? Skip it. There are no streaks, scores, or missed-day penalties.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .dualCamera:
            LocalizedStringResource(
                "Show what you see and how you look in the same photo or video. Your face appears in a small picture-in-picture frame. A single camera works, too.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .voice:
            LocalizedStringResource(
                "Say a few words, write a note, or save the moment without a caption. Time is recorded automatically. Location is optional.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .movie:
            LocalizedStringResource(
                "Find your memories by date or place. Turn a month, a year, or any part of your life into a movie made from real, little moments.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .privacy:
            LocalizedStringResource(
                "Your captures stay on your device by default. You choose when to back up, share, export, or delete them. No public profile is required.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        }
    }

    var primaryAction: LocalizedStringResource {
        self == .privacy
            ? LocalizedStringResource("Set up reminders", bundle: .atURL(Bundle.module.bundleURL))
            : LocalizedStringResource("Continue", bundle: .atURL(Bundle.module.bundleURL))
    }

    /// The last page leads into reminder setup, so it has no Skip.
    var canSkip: Bool { self != .privacy }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
}

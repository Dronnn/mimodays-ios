import Foundation

/// The educational pages in order: OB-01 to OB-06 (doc 01 §5), with §V17 LL01 and LL02 (1.0.7) after the voice.
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case surprise
    case dualCamera
    case voice
    /// LL01: the new ways to catch a moment.
    case ways
    /// LL02: the widgets.
    case widgets
    case movie
    case privacy

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .welcome: LocalizedStringResource("Your life, in little pieces.", bundle: .atURL(Bundle.module.bundleURL))
        case .surprise: LocalizedStringResource("A surprise comes. Capture it now.", bundle: .atURL(Bundle.module.bundleURL), comment: "Onboarding OB-02 title: the app's main idea")
        case .dualCamera: LocalizedStringResource("You and the world around you.", bundle: .atURL(Bundle.module.bundleURL))
        case .voice: LocalizedStringResource("Give your moment a voice.", bundle: .atURL(Bundle.module.bundleURL))
        case .ways: LocalizedStringResource("Catch it your way.", bundle: .atURL(Bundle.module.bundleURL), comment: "Onboarding LL01 title: the new ways to catch a moment")
        case .widgets: LocalizedStringResource("Memories on your Home Screen.", bundle: .atURL(Bundle.module.bundleURL), comment: "Onboarding LL02 title: the widgets")
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
                "That's the whole idea: at a random time, MimoDays sends a notification. Drop what you're doing and, wherever you are, capture what's around you right away, just as it is. Busy? Skip it. No streaks, no penalties.",
                bundle: .atURL(Bundle.module.bundleURL),
                comment: "Onboarding OB-02: the app's main idea; a notification comes, you stop and capture at once"
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
        case .ways:
            LocalizedStringResource(
                "Open the camera with one press from the Lock Screen, Control Center or the Action button. Write a moment in words, bring in photos, Live Photos and videos from your library, or pick a Journaling Suggestion.",
                bundle: .atURL(Bundle.module.bundleURL),
                comment: "Onboarding LL01: the camera control, text moments, photo library import, Journaling Suggestions"
            )
        case .widgets:
            LocalizedStringResource(
                "Add the On this day and Random memory widgets. They show photos only if you turn that on, and nothing private while App Lock is on.",
                bundle: .atURL(Bundle.module.bundleURL),
                comment: "Onboarding LL02: the Home Screen widgets and their privacy"
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

    /// The number progress is saved under. The 1.0.7 pages take new numbers, so an onboarding left half-way before
    /// the update resumes on the page it was on.
    var savedNumber: Int {
        switch self {
        case .welcome: 0
        case .surprise: 1
        case .dualCamera: 2
        case .voice: 3
        case .movie: 4
        case .privacy: 5
        case .ways: 10
        case .widgets: 11
        }
    }

    init?(savedNumber: Int) {
        guard let page = Self.allCases.first(where: { $0.savedNumber == savedNumber }) else { return nil }
        self = page
    }
}

// Generated from the Penpot onboarding art boards (O01-O06), then the photo frames filled with stills from the demo
// footage and two captions changed to match them (2026-11-17).
import DesignSystem
import SwiftUI

extension OnboardingPage {
    var artLayers: [ArtLayer] {
        switch self {
        case .welcome:
            [
                .shape("onboardingWelcome01", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingWelcome02", .photo("onboardingPhotoWelcome02", frame: CGRect(x: 3.6, y: 44.8, width: 197.5, height: 166.4)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("kitchen table", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.hand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 52, y: 71.9), rotation: -4),
                .shape("onboardingWelcome03", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingWelcome04", .photo("onboardingPhotoWelcome04", frame: CGRect(x: 169.7, y: 18.9, width: 187.5, height: 162.6)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("train window", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.hand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 211.7, y: 152.2), rotation: 5),
                .shape("onboardingWelcome05", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingWelcome06", .photo("onboardingPhotoWelcome06", frame: CGRect(x: 102.0, y: 187.7, width: 188.3, height: 157.9)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("good dog", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.hand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 146, y: 326.3), rotation: -2),
                .shape("onboardingWelcome07", .token(.accentApricot), shadow: nil),
                .shape("onboardingWelcome08", .token(.accentCoralMark), shadow: nil),
                .shape("onboardingWelcome09", .token(.accentSage), shadow: nil),
            ]
        case .surprise:
            [
                .shape("onboardingSurprise01", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingSurprise02", .photo("onboardingPhotoSurprise02", frame: CGRect(x: 5, y: 35, width: 352, height: 290)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.14, radius: 7, y: 4)),
                .shape("onboardingSurprise03", .token(.mediaFrame), shadow: nil),
                .text(.localized(LocalizedStringResource("an ordinary afternoon", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.hand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 96, y: 290.5), rotation: 0),
                .shape("onboardingSurprise04", .token(.surfaceCard, opacity: 0.94), shadow: ArtShadow(color: 0x4A2734, opacity: 0.16, radius: 12, y: 8)),
                .shape("onboardingSurprise05", .brandGradient, shadow: ArtShadow(color: 0x4B2938, opacity: 0.2, radius: 6, y: 4)),
                .shape("onboardingSurprise06", .token(.textOnCoral), shadow: nil),
                .text(.verbatim("MIMODAYS"), TextStyle(.label, size: 12, weight: 600, tracking: 0.4, isUppercase: false, relativeTo: .body), .textSecondary, center: CGPoint(x: 97.5, y: 107.5), rotation: 0),
                .text(.localized(LocalizedStringResource("now", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.label, size: 13, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textSecondary, center: CGPoint(x: 325, y: 107), rotation: 0),
                .text(.localized(LocalizedStringResource("A little moment is happening.", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.label, size: 15, weight: 700, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 169, y: 129), rotation: 0, width: 220),
                .text(.localized(LocalizedStringResource("Look around. This could be a memory.", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.label, size: 15, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 198, y: 149), rotation: 0, width: 276),
                .shape("onboardingSurprise07", .token(.accentApricot), shadow: nil),
                .shape("onboardingSurprise08", .token(.actionCoral), shadow: nil),
            ]
        case .dualCamera:
            [
                .shape("onboardingDualCamera01", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingDualCamera02", .photo("onboardingPhotoDualCamera02", frame: CGRect(x: 5, y: 45, width: 352, height: 290)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.14, radius: 7, y: 4)),
                .shape("onboardingDualCamera03", .token(.mediaFrame), shadow: nil),
                .text(.localized(LocalizedStringResource("the world around you", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.hand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 91, y: 300.5), rotation: 0),
                .shape("onboardingDualCamera04", .token(.mediaFrame), shadow: ArtShadow(color: 0x4B2938, opacity: 0.2, radius: 6, y: 4)),
                .shape("onboardingDualCamera05", .photo("onboardingPhotoDualCamera05", frame: CGRect(x: 243.2, y: 5.2, width: 105.3, height: 132.6), rotation: -5.4), shadow: nil),
                .text(.localized(LocalizedStringResource("you", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.hand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 269.2, y: 122.2), rotation: -5.4, width: 60),
                .shape("onboardingDualCamera06", .token(.accentApricot), shadow: nil),
            ]
        case .voice:
            [
                .shape("onboardingVoice01", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingVoice02", .photo("onboardingPhotoVoice02", frame: CGRect(x: 7.5, y: 11.3, width: 227.6, height: 233.0)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .shape("onboardingVoice03", .token(.surfaceCard), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingVoice04", .token(.actionCoral), shadow: nil),
                .shape("onboardingVoice05", .token(.textOnCoral), shadow: nil),
                .shape("onboardingVoice06", .token(.textPrimary), shadow: nil),
                .shape("onboardingVoice07", .token(.accentPeach), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("Coffee, rain, and one stubborn bug.", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.hand, size: 19, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 156.5, y: 295.8), rotation: -2),
                .shape("onboardingVoice08", .token(.surfaceChip), shadow: nil),
                .shape("onboardingVoice09", .token(.textPrimary), shadow: nil),
                .text(.localized(LocalizedStringResource("Tbilisi · optional", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.body, size: 14, weight: 600, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 121, y: 343), rotation: 0, width: 106),
                .shape("onboardingVoice10", .token(.actionCoral), shadow: nil),
            ]
        case .ways:
            [
                .shape("onboardingWays01", .placeholder(0x4B2938), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .text(.verbatim("9:41"), TextStyle(.label, size: 26, weight: 700, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 80, y: 248), rotation: 0),
                .shape("onboardingWays10", .token(.textOnCoral, opacity: 0.22), shadow: nil),
                .shape("onboardingWays11", .token(.textOnCoral), shadow: nil),
                .shape("onboardingWays02", .token(.surfaceCard), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .text(.localized(LocalizedStringResource("Lena rode her bike all the way to the lake.", bundle: .atURL(Bundle.module.bundleURL), comment: "Onboarding art: a moment written in words")), TextStyle(.hand, size: 15, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 80, y: 71), rotation: 0, width: 112, leadingLines: 3),
                .shape("onboardingWays03", .token(.textLink), shadow: nil),
                .text(.localized(LocalizedStringResource("in words", bundle: .atURL(Bundle.module.bundleURL), comment: "Onboarding art caption: a text moment")), TextStyle(.hand, size: 15, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textSecondary, center: CGPoint(x: 79, y: 187), rotation: 0, width: 110, leadingLines: 1),
                .shape("onboardingWays04", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingWays05", .photo("onboardingPhotoWelcome04", frame: CGRect(x: 191.7, y: 9.7, width: 154.2, height: 156.7), rotation: 6), shadow: nil),
                .shape("onboardingWays06", .token(.surfaceCard, opacity: 0.9), shadow: nil),
                .text(.verbatim("LIVE"), TextStyle(.label, size: 11, weight: 700, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 229, y: 30), rotation: 0),
                .text(.localized(LocalizedStringResource("from your Photos", bundle: .atURL(Bundle.module.bundleURL), comment: "Onboarding art caption: a photo brought in from the library")), TextStyle(.hand, size: 15, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textSecondary, center: CGPoint(x: 283, y: 193), rotation: 0, width: 130, leadingLines: 1),
                .text(.localized(LocalizedStringResource("one press", bundle: .atURL(Bundle.module.bundleURL), comment: "Onboarding art caption: the camera control on the Lock Screen")), TextStyle(.hand, size: 15, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textSecondary, center: CGPoint(x: 99, y: 353), rotation: 0, width: 110, leadingLines: 1),
                .shape("onboardingWays07", .token(.surfaceCard), shadow: ArtShadow(color: 0x2A1B21, opacity: 0.12, radius: 12, y: 4)),
                .shape("onboardingWays08", .photo("onboardingPhotoMovie09", frame: CGRect(x: 188, y: 240, width: 53.1, height: 55.2)), shadow: nil),
                .text(.localized(LocalizedStringResource("Morning walk", bundle: .atURL(Bundle.module.bundleURL), comment: "Onboarding art: the title of a Journaling Suggestion")), TextStyle(.label, size: 14, weight: 700, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 302.5, y: 253), rotation: 0, width: 105, leadingLines: 1),
                .text(.localized(LocalizedStringResource("Riverside · 7:40 AM", bundle: .atURL(Bundle.module.bundleURL), comment: "Onboarding art: the place and time of a Journaling Suggestion")), TextStyle(.label, size: 12, weight: 500, tracking: 0, isUppercase: false, relativeTo: .body), .textSecondary, center: CGPoint(x: 302.5, y: 272), rotation: 0, width: 105, leadingLines: 1),
                .shape("onboardingWays09", .token(.actionCoral), shadow: nil),
                .text(.localized(LocalizedStringResource("Journaling Suggestion", bundle: .atURL(Bundle.module.bundleURL), comment: "Onboarding art: Apple's Journaling Suggestions, one of them")), TextStyle(.label, size: 12, weight: 600, tracking: 0, isUppercase: false, relativeTo: .body), .textLink, center: CGPoint(x: 280, y: 312), rotation: 0, width: 140, leadingLines: 1),
            ]
        case .widgets:
            [
                .shape("onboardingWidgets07", .token(.surfaceChip, opacity: 0.7), shadow: nil),
                .shape("onboardingWidgets01", .token(.surfaceCard), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .text(.localized(LocalizedStringResource("On this day", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.body, size: 13, weight: 800, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 90.5, y: 59), rotation: 0, width: 145, leadingLines: 1),
                .text(.localized(LocalizedStringResource("Random memory", bundle: .atURL(Bundle.module.bundleURL), comment: "The Random memory widget's name")), TextStyle(.body, size: 13, weight: 800, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 274.5, y: 59), rotation: 0, width: 145, leadingLines: 1),
                .shape("onboardingWidgets02", .token(.mediaFrame), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .shape("onboardingWidgets03", .photo("onboardingPhotoWelcome02", frame: CGRect(x: 18.4, y: 73.4, width: 139.8, height: 112.7), rotation: 3), shadow: nil),
                .shape("onboardingWidgets04", .photo("onboardingPhotoMovie02", frame: CGRect(x: 202.4, y: 73.4, width: 139.8, height: 112.7), rotation: 3), shadow: nil),
                .text(.verbatim("2025"), TextStyle(.body, size: 12, weight: 700, tracking: 0, isUppercase: false, relativeTo: .body), .textLink, center: CGPoint(x: 144, y: 194), rotation: 0),
                .shape("onboardingWidgets05", .token(.surfaceChip), shadow: nil),
                .shape("onboardingWidgets06", .token(.textPrimary), shadow: nil),
            ]
        case .movie:
            [
                .shape("onboardingMovie01", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingMovie02", .photo("onboardingPhotoMovie02", frame: CGRect(x: 5, y: 5, width: 352, height: 196)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.14, radius: 7, y: 4)),
                .shape("onboardingMovie03", .token(.mediaFrame), shadow: nil),
                .shape("onboardingMovie04", .token(.mediaFrame, opacity: 0.9), shadow: ArtShadow(color: 0x000000, opacity: 0.2, radius: 7, y: 4)),
                .shape("onboardingMovie05", .token(.textPrimary), shadow: nil),
                .shape("onboardingMovie06", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingMovie07", .photo("onboardingPhotoMovie07", frame: CGRect(x: 4.8, y: 226.2, width: 74.1, height: 73.5)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("Winter", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.body, size: 12, weight: 800, tracking: 1, isUppercase: true, relativeTo: .body), .textSecondary, center: CGPoint(x: 42, y: 321.5), rotation: 0, width: 88),
                .shape("onboardingMovie08", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingMovie09", .photo("onboardingPhotoMovie09", frame: CGRect(x: 97.3, y: 227.4, width: 75.1, height: 72.2)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("Spring", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.body, size: 12, weight: 800, tracking: 1, isUppercase: true, relativeTo: .body), .textSecondary, center: CGPoint(x: 135, y: 321.5), rotation: 0, width: 88),
                .shape("onboardingMovie10", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingMovie11", .photo("onboardingPhotoMovie11", frame: CGRect(x: 190.6, y: 226.8, width: 73.5, height: 72.1)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("Summer", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.body, size: 12, weight: 800, tracking: 1, isUppercase: true, relativeTo: .body), .textSecondary, center: CGPoint(x: 227, y: 321.5), rotation: 0, width: 88),
                .shape("onboardingMovie12", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingMovie13", .photo("onboardingPhotoMovie13", frame: CGRect(x: 282.4, y: 227.1, width: 75.3, height: 72.2)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("Autumn", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.body, size: 12, weight: 800, tracking: 1, isUppercase: true, relativeTo: .body), .textSecondary, center: CGPoint(x: 320, y: 321.5), rotation: 0, width: 88),
                .shape("onboardingMovie14", .token(.actionCoral), shadow: nil),
            ]
        case .privacy:
            [
                .shape("onboardingPrivacy01", .token(.surfaceCard), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingPrivacy02", .photo("onboardingPhotoPrivacy02", frame: CGRect(x: 78.0, y: 49.8, width: 206.3, height: 164.4)), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .shape("onboardingPrivacy03", .token(.accentPeach), shadow: nil),
                .shape("onboardingPrivacy04", .token(.textPrimary), shadow: nil),
                .shape("onboardingPrivacy05", .token(.accentApricot), shadow: nil),
                .shape("onboardingPrivacy06", .token(.accentSage), shadow: nil),
            ]
        }
    }
}

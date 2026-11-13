// Generated from the Penpot onboarding art boards (O01-O06). Regenerate instead of editing by hand.
import DesignSystem
import SwiftUI

extension OnboardingPage {
    var artLayers: [ArtLayer] {
        switch self {
        case .welcome:
            [
                .shape("onboardingWelcome01", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingWelcome02", .placeholder(0xB9A595), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("kitchen table", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.patrickHand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 52, y: 71.9), rotation: -4),
                .shape("onboardingWelcome03", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingWelcome04", .placeholder(0xC9B5A3), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("bus window", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.patrickHand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 211.7, y: 152.2), rotation: 5),
                .shape("onboardingWelcome05", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingWelcome06", .placeholder(0xA48D7C), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("dog asleep", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.patrickHand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 146, y: 326.3), rotation: -2),
                .shape("onboardingWelcome07", .token(.accentApricot), shadow: nil),
                .shape("onboardingWelcome08", .token(.accentCoralMark), shadow: nil),
                .shape("onboardingWelcome09", .token(.accentSage), shadow: nil),
            ]
        case .surprise:
            [
                .shape("onboardingSurprise01", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingSurprise02", .placeholder(0xB49F8D), shadow: ArtShadow(color: 0x4B2938, opacity: 0.14, radius: 7, y: 4)),
                .shape("onboardingSurprise03", .token(.mediaFrame), shadow: nil),
                .text(.localized(LocalizedStringResource("an ordinary afternoon", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.patrickHand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 96, y: 290.5), rotation: 0),
                .shape("onboardingSurprise04", .token(.surfaceCard, opacity: 0.94), shadow: ArtShadow(color: 0x4A2734, opacity: 0.16, radius: 12, y: 8)),
                .shape("onboardingSurprise05", .brandGradient, shadow: ArtShadow(color: 0x4B2938, opacity: 0.2, radius: 6, y: 4)),
                .shape("onboardingSurprise06", .token(.textOnCoral), shadow: nil),
                .text(.verbatim("MIMODAYS"), TextStyle(.inter, size: 12, weight: 600, tracking: 0.4, isUppercase: false, relativeTo: .body), .textSecondary, center: CGPoint(x: 97.5, y: 107.5), rotation: 0),
                .text(.localized(LocalizedStringResource("now", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.inter, size: 13, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textSecondary, center: CGPoint(x: 325, y: 107), rotation: 0),
                .text(.localized(LocalizedStringResource("A little moment is happening.", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.inter, size: 15, weight: 700, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 169, y: 129), rotation: 0),
                .text(.localized(LocalizedStringResource("Look around. This could be a memory.", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.inter, size: 15, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 198, y: 149), rotation: 0),
                .shape("onboardingSurprise07", .token(.accentApricot), shadow: nil),
                .shape("onboardingSurprise08", .token(.actionCoral), shadow: nil),
            ]
        case .dualCamera:
            [
                .shape("onboardingDualCamera01", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingDualCamera02", .placeholder(0xA08A79), shadow: ArtShadow(color: 0x4B2938, opacity: 0.14, radius: 7, y: 4)),
                .shape("onboardingDualCamera03", .token(.mediaFrame), shadow: nil),
                .text(.localized(LocalizedStringResource("the world around you", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.patrickHand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 91, y: 300.5), rotation: 0),
                .shape("onboardingDualCamera04", .token(.mediaFrame), shadow: ArtShadow(color: 0x4B2938, opacity: 0.2, radius: 6, y: 4)),
                .shape("onboardingDualCamera05", .placeholder(0xB9A89A), shadow: nil),
                .text(.localized(LocalizedStringResource("you", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.patrickHand, size: 17, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textOnCoral, center: CGPoint(x: 269.2, y: 122.2), rotation: -5.4),
                .shape("onboardingDualCamera06", .token(.accentApricot), shadow: nil),
            ]
        case .voice:
            [
                .shape("onboardingVoice01", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingVoice02", .placeholder(0xB7A190), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .shape("onboardingVoice03", .token(.surfaceCard), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingVoice04", .token(.actionCoral), shadow: nil),
                .shape("onboardingVoice05", .token(.textOnCoral), shadow: nil),
                .shape("onboardingVoice06", .token(.textPrimary), shadow: nil),
                .shape("onboardingVoice07", .token(.accentPeach), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("Coffee, rain, and one stubborn bug.", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.patrickHand, size: 19, weight: 400, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 156.5, y: 295.8), rotation: -2),
                .shape("onboardingVoice08", .token(.surfaceChip), shadow: nil),
                .shape("onboardingVoice09", .token(.textPrimary), shadow: nil),
                .text(.localized(LocalizedStringResource("Tbilisi · optional", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.nunito, size: 14, weight: 600, tracking: 0, isUppercase: false, relativeTo: .body), .textPrimary, center: CGPoint(x: 121, y: 343), rotation: 0),
                .shape("onboardingVoice10", .token(.actionCoral), shadow: nil),
            ]
        case .movie:
            [
                .shape("onboardingMovie01", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingMovie02", .placeholder(0x7E6A5E), shadow: ArtShadow(color: 0x4B2938, opacity: 0.14, radius: 7, y: 4)),
                .shape("onboardingMovie03", .token(.mediaFrame), shadow: nil),
                .shape("onboardingMovie04", .token(.mediaFrame, opacity: 0.9), shadow: ArtShadow(color: 0x000000, opacity: 0.2, radius: 7, y: 4)),
                .shape("onboardingMovie05", .token(.textPrimary), shadow: nil),
                .shape("onboardingMovie06", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingMovie07", .placeholder(0xDCDDD3), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("Winter", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.nunito, size: 12, weight: 800, tracking: 1, isUppercase: true, relativeTo: .body), .textSecondary, center: CGPoint(x: 42, y: 321.5), rotation: 0),
                .shape("onboardingMovie08", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingMovie09", .placeholder(0xD8DBC1), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("Spring", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.nunito, size: 12, weight: 800, tracking: 1, isUppercase: true, relativeTo: .body), .textSecondary, center: CGPoint(x: 135, y: 321.5), rotation: 0),
                .shape("onboardingMovie10", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingMovie11", .placeholder(0xF6D7A6), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("Summer", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.nunito, size: 12, weight: 800, tracking: 1, isUppercase: true, relativeTo: .body), .textSecondary, center: CGPoint(x: 227, y: 321.5), rotation: 0),
                .shape("onboardingMovie12", .token(.mediaFrame), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingMovie13", .placeholder(0xEFC2A8), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .text(.localized(LocalizedStringResource("Autumn", bundle: .atURL(Bundle.module.bundleURL))), TextStyle(.nunito, size: 12, weight: 800, tracking: 1, isUppercase: true, relativeTo: .body), .textSecondary, center: CGPoint(x: 320, y: 321.5), rotation: 0),
                .shape("onboardingMovie14", .token(.actionCoral), shadow: nil),
            ]
        case .privacy:
            [
                .shape("onboardingPrivacy01", .token(.surfaceCard), shadow: ArtShadow(color: 0x4A2734, opacity: 0.14, radius: 9, y: 6)),
                .shape("onboardingPrivacy02", .placeholder(0xB9A595), shadow: ArtShadow(color: 0x4B2938, opacity: 0.1, radius: 3, y: 2)),
                .shape("onboardingPrivacy03", .token(.accentPeach), shadow: nil),
                .shape("onboardingPrivacy04", .token(.textPrimary), shadow: nil),
                .shape("onboardingPrivacy05", .token(.accentApricot), shadow: nil),
                .shape("onboardingPrivacy06", .token(.accentSage), shadow: nil),
            ]
        }
    }
}

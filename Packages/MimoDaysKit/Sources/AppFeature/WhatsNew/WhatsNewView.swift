import DesignSystem
import Foundation
import SwiftUI

/// §V17 LL03: whether this release's What's new is still to show. A new install meets the onboarding pages instead.
struct WhatsNewSettings: Codable, Equatable, Sendable {
    static let release = "1.0.7"
    /// The release whose What's new was shown, or wasn't needed.
    var seenRelease: String?

    var isDue: Bool { seenRelease != Self.release }
}

typealias WhatsNewPreferences = DevicePreference<WhatsNewSettings>

extension DevicePreference<WhatsNewSettings> {
    /// `seen`: the first-launch value, for UI tests that keep nothing between launches.
    static func whatsNew(_ defaults: UserDefaults?, seen: Bool) -> WhatsNewPreferences {
        WhatsNewPreferences(key: "whatsNew", defaults: defaults, initial: WhatsNewSettings(seenRelease: seen ? WhatsNewSettings.release : nil))
    }

    func markSeen() {
        value.seenRelease = WhatsNewSettings.release
    }
}

/// LL03: once, over Today, for someone who used MimoDays before 1.0.7. Continue closes it for good.
struct WhatsNewView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("What's new in MimoDays", bundle: .module, comment: "What's new (LL03) title, shown once after the 1.0.7 update")
                    .textStyle(.displayHeadline)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 38)
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(WhatsNewItem.allCases, id: \.self) { WhatsNewRow(item: $0) }
                }
                .padding(.top, 36)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 402, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onContinue) { Text("Continue", bundle: .module) }
                .buttonStyle(.primary)
                .accessibilityIdentifier("whatsNew.continue")
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .frame(maxWidth: 402)
                .frame(maxWidth: .infinity)
                .background(ColorToken.canvas.color.ignoresSafeArea(edges: .bottom))
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .accessibilityIdentifier("whatsNew")
    }
}

enum WhatsNewItem: CaseIterable {
    case camera, widgets, words, photos, suggestions

    var glyph: Icon {
        switch self {
        case .camera: .glyphCamera
        case .widgets: .glyphCollection
        case .words: .glyphText
        case .photos: .glyphPhotos
        case .suggestions: .glyphSparkle
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .camera: LocalizedStringResource("The camera in one press", bundle: .atURL(Bundle.module.bundleURL), comment: "What's new row title")
        case .widgets: LocalizedStringResource("Widgets", bundle: .atURL(Bundle.module.bundleURL))
        case .words: LocalizedStringResource("Moments in words", bundle: .atURL(Bundle.module.bundleURL), comment: "What's new row title: text moments")
        case .photos: LocalizedStringResource("From your photo library", bundle: .atURL(Bundle.module.bundleURL), comment: "What's new row title: importing from Photos")
        case .suggestions: LocalizedStringResource("Journaling Suggestions", bundle: .atURL(Bundle.module.bundleURL), comment: "What's new row title: Apple's Journaling Suggestions")
        }
    }

    var line: LocalizedStringResource {
        switch self {
        case .camera:
            LocalizedStringResource("From the Lock Screen, Control Center, Siri or the Action button.", bundle: .atURL(Bundle.module.bundleURL), comment: "What's new row: where the camera control is")
        case .widgets:
            LocalizedStringResource("On this day and Random memory on your Home Screen.", bundle: .atURL(Bundle.module.bundleURL), comment: "What's new row: the two widgets")
        case .words:
            LocalizedStringResource("Write a moment when there's nothing to film.", bundle: .atURL(Bundle.module.bundleURL), comment: "What's new row: text moments")
        case .photos:
            LocalizedStringResource("Bring in photos, Live Photos and videos.", bundle: .atURL(Bundle.module.bundleURL), comment: "What's new row: importing from Photos")
        case .suggestions:
            LocalizedStringResource("Start a moment from a suggestion iOS makes on your iPhone.", bundle: .atURL(Bundle.module.bundleURL), comment: "What's new row: Journaling Suggestions")
        }
    }
}

/// A hand-cut peach tile with the glyph, then the title and its line; one element to VoiceOver.
private struct WhatsNewRow: View {
    let item: WhatsNewItem

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            item.glyph.image
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: 48, height: 50)
                .background(GlyphTileBlob().fill(ColorToken.accentPeach.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .textStyle(TextStyle(.label, size: 17, weight: 700, lineHeight: 1.2, relativeTo: .headline))
                    .foregroundStyle(ColorToken.textPrimary.color)
                Text(item.line)
                    .textStyle(TextStyle(.label, size: 15, weight: 400, lineHeight: 1.2, relativeTo: .subheadline))
                    .foregroundStyle(ColorToken.textSecondary.color)
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

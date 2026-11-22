import DesignSystem
import SwiftUI
import Testing
import TestSupport
import UIKit
import WidgetFeature

/// §V6 AA01/AA02: the widgets on a Home Screen, with photos, words only, empty, App Lock and the gallery tile.
@MainActor
@Suite(.tags(.snapshot)) struct WidgetSnapshotTests {
    private let photo = WidgetPayload.Memory(id: UUID(), day: 20_251_121, place: "Paris", kind: .photo, image: "a.jpg")
    private let video = WidgetPayload.Memory(id: UUID(), day: 20_250_308, place: "Paris", kind: .video)
    private let words = WidgetPayload.Memory(id: UUID(), day: 20_240_101, place: nil, kind: .text)

    private var picture: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 240)).image { context in
            let colors = [UIColor(red: 0.62, green: 0.84, blue: 0.76, alpha: 1).cgColor, UIColor(red: 0.37, green: 0.65, blue: 0.56, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 300, y: 240), options: [])
        }
    }

    private func onThisDay(_ cover: WidgetPayload.Memory) -> WidgetContent.OnThisDay {
        .memory(WidgetPayload.Day(today: 20_261_121, count: 3, cover: cover))
    }

    private let another: AnotherButton = { $0 }

    @Test func withPhotos() {
        let board = HomeScreen {
            HStack(spacing: 14) {
                Small { OnThisDayWidgetView(content: onThisDay(photo), isMedium: false, image: picture) }
                Small { RandomMemoryWidgetView(content: .memory(photo, canSwap: true), isMedium: false, showsPhotos: true, image: picture, another: another) }
            }
            Medium { RandomMemoryWidgetView(content: .memory(photo, canSwap: true), isMedium: true, showsPhotos: true, image: picture, another: another) }
            HStack(spacing: 14) {
                Small { RandomMemoryWidgetView(content: .memory(words, canSwap: false), isMedium: false, showsPhotos: true, image: nil, another: another) }
                Small { OnThisDayWidgetView(content: .placeholder, isMedium: false, image: nil) }
            }
            Medium { OnThisDayWidgetView(content: onThisDay(photo), isMedium: true, image: picture) }
        }
        assertScreenSnapshots(
            of: board,
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
                + SnapshotVariant.languages
        )
    }

    @Test func wordsEmptyAndLocked() {
        let board = HomeScreen {
            HStack(spacing: 14) {
                Small { OnThisDayWidgetView(content: onThisDay(video), isMedium: false, image: nil) }
                Small { OnThisDayWidgetView(content: .empty, isMedium: false, image: nil) }
            }
            Medium { RandomMemoryWidgetView(content: .memory(video, canSwap: true), isMedium: true, showsPhotos: false, image: nil, another: another) }
            HStack(spacing: 14) {
                Small { OnThisDayWidgetView(content: .locked, isMedium: false, image: nil) }
                Small { RandomMemoryWidgetView(content: .memory(video, canSwap: true), isMedium: false, showsPhotos: false, image: nil, another: another) }
            }
            HStack(spacing: 14) {
                Small { RandomMemoryWidgetView(content: .empty, isMedium: false, showsPhotos: false, image: nil, another: another) }
                Small { RandomMemoryWidgetView(content: .locked, isMedium: false, showsPhotos: false, image: nil, another: another) }
            }
        }
        assertScreenSnapshots(
            of: board,
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
                + SnapshotVariant.languages
        )
    }
}

/// A Home Screen wallpaper with widgets laid out as iOS does (170 pt small, 354 pt medium on this iPhone).
private struct HomeScreen<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 14) { content }
            .padding(.top, 76)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LinearGradient(colors: [Color(red: 0.76, green: 0.66, blue: 0.6), Color(red: 0.55, green: 0.42, blue: 0.4)], startPoint: .top, endPoint: .bottom))
    }
}

private struct Small<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { WidgetFrame(width: 170) { content } }
}

private struct Medium<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { WidgetFrame(width: 354) { content } }
}

/// The widget's own shape and background are drawn by iOS; here a stand-in.
private struct WidgetFrame<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: width, height: 170)
            .background(ColorToken.surfaceCard.color)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

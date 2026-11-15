import DesignSystem
import SwiftUI

/// D01 with the app's tip store.
struct DonationsScreen: View {
    @Environment(\.tipStore) private var store

    var body: some View {
        if let store {
            DonationsHost(model: DonationsModel(store: store))
        }
    }
}

private struct DonationsHost: View {
    @State var model: DonationsModel

    var body: some View {
        DonationsView(model: model)
            .task { await model.load() }
    }
}

/// D01-D04: why, the six tips with their App Store prices, and the fine print.
struct DonationsView: View {
    @Bindable var model: DonationsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Settings", bundle: .module), title: Text("Donations", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Keep MimoDays independent.", bundle: .module)
                        .textStyle(.displayHeadline)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    Text("The app is designed, built and maintained by one developer. If it helps you, a tip is appreciated. Every feature stays available either way.", bundle: .module)
                        .textStyle(.sheetBody)
                        .foregroundStyle(ColorToken.textBody.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                    Group {
                        if model.phase == .unavailable {
                            unavailable
                        } else {
                            tiles
                        }
                    }
                    .padding(.top, 26)
                    if let notice = model.notice {
                        DataNote(text: noticeText(notice))
                            .padding(.horizontal, 6)
                            .padding(.top, 12)
                            .accessibilityIdentifier("donations.notice")
                    }
                    DataNote(text: Text("Prices are set by the App Store for your country and charged to your Apple Account. Donations are optional, consumable tips. They do not unlock features.", bundle: .module))
                        .padding(.horizontal, 6)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .sheet(isPresented: $model.showsThankYou) {
            ThankYouSheet()
        }
    }

    private var tiles: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: typeSize.isAccessibilitySize ? 1 : 2)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(model.tiers) { tier in
                TipTile(tier: tier, price: model.prices[tier], isPurchasing: model.purchasing == tier) {
                    Task { await model.buy(tier) }
                }
                .disabled(model.phase != .ready || model.purchasing != nil)
            }
        }
    }

    /// D04.
    private var unavailable: some View {
        VStack(spacing: 10) {
            Icon.glyphInfo.image
                .resizable()
                .frame(width: 22, height: 22)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityHidden(true)
            Text("Donations are not available right now.", bundle: .module)
                .textStyle(.control)
                .foregroundStyle(ColorToken.textPrimary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 118)
        .background { InfoCardBlob().fill(ColorToken.surfaceCard.color) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("donations.unavailable")
    }

    private func noticeText(_ notice: DonationsModel.Notice) -> Text {
        switch notice {
        case .failed: Text("The tip didn't go through. Please try again.", bundle: .module)
        case .pending: Text("Waiting for approval. The tip goes through once it's approved.", bundle: .module)
        }
    }
}

/// D01 `Donation / Tier`.
private struct TipTile: View {
    let tier: TipTier
    /// Nil while prices load.
    let price: String?
    let isPurchasing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                tier.icon.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(ColorToken.accentPeach.color))
                    .accessibilityHidden(true)
                tier.title
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                pill.padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background {
                TipTileBlob()
                    .fill(ColorToken.surfaceCard.color)
                    .shadow(color: Color(red: 0x4B / 255, green: 0x29 / 255, blue: 0x38 / 255).opacity(0.08), radius: 4, y: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("donations.\(tier.rawValue)")
    }

    /// The price on coral; "…" on the chip colour while it loads or its payment sheet is up (D02).
    @ViewBuilder private var pill: some View {
        let waiting = isPurchasing || price == nil
        Text(verbatim: waiting ? "…" : price ?? "")
            .textStyle(TextStyle(.nunito, size: 14, weight: 800, relativeTo: .subheadline))
            .foregroundStyle((waiting ? ColorToken.textPrimary : ColorToken.textOnCoral).color)
            .padding(.horizontal, 12)
            .frame(minWidth: 62, minHeight: 26)
            .background(Capsule().fill((waiting ? ColorToken.surfaceChip : ColorToken.actionCoral).color))
            .accessibilityLabel(waiting ? Text("Waiting", bundle: .module) : Text(verbatim: price ?? ""))
    }
}

extension TipTier {
    var title: Text {
        switch self {
        case .small: Text("Tip size: small", bundle: .module)
        case .medium: Text("Tip size: medium", bundle: .module)
        case .large: Text("Tip size: large", bundle: .module)
        case .generous: Text("Tip size: generous", bundle: .module)
        case .patron: Text("Tip size: patron", bundle: .module)
        case .extraordinary: Text("Tip size: extraordinary", bundle: .module)
        }
    }

    var icon: Icon {
        switch self {
        case .small: .glyphCup
        case .medium: .glyphBag
        case .large: .glyphHeart
        case .generous: .glyphStar
        case .patron: .glyphCrown
        case .extraordinary: .glyphSparkle
        }
    }
}

/// D03.
struct ThankYouSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ExplainerArt(glyph: .glyphHeart, blob: .accentMint)
                .accessibilityHidden(true)
                .padding(.top, 24)
            Text("Thank you!", bundle: .module)
                .textStyle(.displaySheet)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 12)
            Text("Your support keeps the app going.", bundle: .module)
                .textStyle(.sheetBody)
                .foregroundStyle(ColorToken.textBody.color)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Spacer(minLength: 24)
            Button { dismiss() } label: { Text("Done", bundle: .module) }
                .buttonStyle(.primary)
                .accessibilityIdentifier("donations.done")
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(ColorToken.surfaceSheet.color.ignoresSafeArea())
        .presentationDetents([.height(380), .large])
        .presentationDragIndicator(.visible)
    }
}

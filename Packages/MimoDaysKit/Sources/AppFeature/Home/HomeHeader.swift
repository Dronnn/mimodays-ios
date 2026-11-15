import DesignSystem
import SwiftUI

/// The home header (T02, U10, U13): the wordmark, the Today | Mosaic switch, settings.
struct HomeHeader: View {
    /// iPad landscape's tighter edges (X01).
    var isWide = false
    @Environment(AppRouter.self) private var router
    @Environment(Home.self) private var home: Home?

    var body: some View {
        // The wordmark sets the height (T02); the switch sits level with it, 125 pt from its start (U10), and the gear
        // hangs a little lower in the corner.
        wordmark
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if let home {
                    HomeSideSwitch(side: home.side) { home.show($0) }
                        .padding(.leading, 125)
                        .padding(.top, 3)
                }
            }
            .overlay(alignment: .topTrailing) { settings }
        .padding(.leading, isWide ? 12 : 25)
        .padding(.trailing, isWide ? 8 : 19)
    }

    private var wordmark: some View {
        ZStack {
            Icon.brandWordmark.image.resizable().foregroundStyle(ColorToken.textPrimary.color)
            Icon.brandWordmarkStar.image.resizable().foregroundStyle(ColorToken.actionCoral.color)
        }
        .frame(width: 103.7, height: 33)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "MimoDays"))
        .accessibilityAddTraits(.isHeader)
    }

    /// The gear hangs a little lower than the wordmark (T02).
    private var settings: some View {
        Button { router.open(.settings) } label: {
            Icon.glyphGear.image
                .resizable()
                .frame(width: 22, height: 22)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(ColorToken.textPrimary.color, lineWidth: 1.3))
                .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Settings", bundle: .module))
        .accessibilityIdentifier("settings")
        .offset(y: 2)
    }
}

/// `Home / Side switch`: Today and Mosaic on a cream capsule, the side shown on a plum thumb.
struct HomeSideSwitch: View {
    let side: HomeSide
    let choose: (HomeSide) -> Void
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 3) {
            option(.today, Text("Today", bundle: .module), width: 66)
            option(.mosaic, Text("Mosaic", bundle: .module), width: 75)
        }
        .padding(3)
        .background(Capsule().fill(Self.track))
        .overlay(Capsule().strokeBorder(ColorToken.textPrimary.color.opacity(side == .mosaic ? 0.08 : 0), lineWidth: 1))
        .animation(.snappy, value: side)
    }

    private func option(_ option: HomeSide, _ title: Text, width: CGFloat) -> some View {
        let isOn = option == side
        return Button { choose(option) } label: {
            title
                .textStyle(.homeSwitch)
                .foregroundStyle(isOn ? Self.onLabel : Self.offLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: width, minHeight: 30)
                .background {
                    if isOn {
                        Capsule().fill(Self.thumbFill).matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .frame(minHeight: Size.minimumTapTarget)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(option == .today ? "home.today" : "home.mosaic")
    }

    /// U10/U13 in the light, U15 in the dark: a cream track with a plum thumb, a plum one with a coral thumb.
    private static let track = Color.dynamic(light: 0xF3E8DE, dark: 0x2E262C)
    private static let thumbFill = Color.dynamic(light: 0x4B2938, dark: 0xF2896A)
    private static let onLabel = Color.dynamic(light: 0xFBF6EF, dark: 0x211C24)
    private static let offLabel = Color.dynamic(light: 0x4B2938, dark: 0xF3E8DE)
}

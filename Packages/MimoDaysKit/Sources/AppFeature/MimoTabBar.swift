import DesignSystem
import SwiftUI

extension MainTab {
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

/// iPhone tab bar from the design (Navigation / Tab bar): hand-cut peach pill behind the selected icon,
/// coral selected label, plum others. Labels hide at accessibility text sizes; VoiceOver still reads them.
struct MimoTabBar: View {
    @Binding var selection: MainTab
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(alignment: .top) {
            ColorToken.canvas.color
                .overlay(alignment: .top) { ColorToken.borderSubtle.color.frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ tab: MainTab) -> some View {
        let isSelected = tab == selection
        let tint = isSelected ? ColorToken.textLink.color : ColorToken.textPrimary.color
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Icon.shapeTabPill.image
                            .resizable()
                            .frame(width: Icon.shapeTabPill.designSize.width, height: Icon.shapeTabPill.designSize.height)
                            .foregroundStyle(ColorToken.accentPeach.color)
                    }
                    tab.icon.image
                        .resizable()
                        .frame(width: tab.icon.designSize.width, height: tab.icon.designSize.height)
                        .foregroundStyle(tint)
                }
                .frame(height: 31)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(tab.title)
                        .textStyle(isSelected ? .tabLabelSelected : .tabLabel)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Size.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }
}

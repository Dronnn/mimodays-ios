import Core
import DesignSystem
import SwiftUI

/// Memories' calendar: a month of covers (M02) or a year of dots (M03). Days are each moment's own local day
/// (§H20); weeks start where the person's region starts them.
struct MemoriesCalendarView: View {
    @Bindable var model: MemoriesModel
    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(spacing: 0) {
            switch model.scale {
            case .month: month
            case .year: year
            }
        }
    }

    // MARK: Month (M02)

    private var month: some View {
        VStack(spacing: 0) {
            navigationRow {
                Button { model.show(year: model.shownMonth / 100) } label: {
                    Text(MemoriesView.monthDate(model.shownMonth), format: Date.FormatStyle(timeZone: .gmt).month(.wide).year())
                        .textStyle(.displaySection)
                        .foregroundStyle(ColorToken.textPrimary.color)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows the whole year", bundle: .module))
                .accessibilityIdentifier("calendar.title")
            } trailing: {
                arrow(forward: true)
            }
            weekdays
                .padding(.top, 12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                // Blanks before the 1st, with ids that can't meet a day's.
                ForEach(Array(0..<leadingBlanks(model.shownMonth)).map { -1 - $0 }, id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(1...daysIn(model.shownMonth), id: \.self) { day in
                    dayCell(model.shownMonth * 100 + day)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 19)
            Rectangle()
                .fill(ColorToken.textPrimary.color.opacity(0.14))
                .frame(height: 0.6)
                .padding(.horizontal, 16)
                .padding(.top, 20)
            selectedRow
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
    }

    private var weekdays: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                Text(symbols[(first + index) % 7])
                    .textStyle(.labelCaps)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 19)
        .accessibilityHidden(true)
    }

    private func dayCell(_ key: Int) -> some View {
        let items = model.days[key] ?? []
        let cover = items.first
        let isSelected = model.selectedDay == key
        let isFuture = key > model.today
        return Button { model.selectedDay = key } label: {
            ZStack(alignment: .bottomLeading) {
                if let cover {
                    Color(hex: 0xC9B8AA)
                        .overlay {
                            if let image = model.images[cover.id] { Image(uiImage: image).resizable().scaledToFill() }
                        }
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [.clear, ColorToken.mediaScrim.color], startPoint: .top, endPoint: .bottom)
                                .frame(height: 26)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .task { await model.load(cover.id) }
                    Text(key % 100, format: .number)
                        .textStyle(.calendarDayOnPhoto)
                        .foregroundStyle(ColorToken.mediaFrame.color)
                        .padding(.leading, 6)
                        .padding(.bottom, 4)
                } else {
                    Text(key % 100, format: .number)
                        .textStyle(.calendarDay)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .opacity(isFuture ? 0.45 : 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(47 / 52, contentMode: .fit)
            .padding(4)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(ColorToken.actionCoral.color, lineWidth: 2.5)
                }
            }
            .padding(-4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(Text("Calendar day: \(Text(MemoriesView.dayDate(key), format: Date.FormatStyle(timeZone: .gmt).weekday(.wide).month(.wide).day())) · \(count(items.count))", bundle: .module))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendar.day.\(key % 100)")
    }

    /// "Wed, Nov 11 · 3 moments" and the way into that day.
    @ViewBuilder
    private var selectedRow: some View {
        if let day = model.selectedDay, day / 100 == model.shownMonth {
            let total = model.days[day]?.count ?? 0
            let label = Text("Selected day: \(Text(MemoriesView.dayDate(day), format: Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day())) · \(count(total))", bundle: .module)
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
            if total > 0 {
                NavigationLink(value: MemoriesRoute.day(day)) {
                    HStack {
                        label
                        Spacer(minLength: 8)
                        Icon.glyphChevron.image
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(ColorToken.textPrimary.color)
                            .flipsForRightToLeftLayoutDirection(true)
                    }
                    .frame(minHeight: Size.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calendar.openDay")
            } else {
                label
                    .frame(maxWidth: .infinity, minHeight: Size.minimumTapTarget, alignment: .leading)
            }
        }
    }

    // MARK: Year (M03)

    private var year: some View {
        VStack(spacing: 0) {
            navigationRow {
                Text(String(model.shownYear))
                    .textStyle(.displaySection)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            } trailing: {
                if model.canGoForward {
                    arrow(forward: true)
                } else {
                    Button { model.show(month: model.thisMonth) } label: {
                        Text("Today", bundle: .module)
                            .textStyle(.control)
                            .foregroundStyle(ColorToken.textLink.color)
                            .frame(minHeight: Size.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("calendar.today")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 16, alignment: .topLeading)], spacing: 22) {
                ForEach(1...12, id: \.self) { month in
                    yearMonth(model.shownYear * 100 + month)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    private func yearMonth(_ key: Int) -> some View {
        let isThisMonth = key == model.thisMonth
        let isFuture = key > model.thisMonth
        let withMoments = (1...daysIn(key)).filter { model.days[key * 100 + $0] != nil }.count
        return Button { model.show(month: key) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(MemoriesView.monthDate(key), format: Date.FormatStyle(timeZone: .gmt).month(.abbreviated))
                    .textStyle(.calendarMonth)
                    .foregroundStyle((isThisMonth ? ColorToken.textLink : .textPrimary).color)
                dots(key)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture || key < model.earliestMonth)
        .accessibilityLabel(Text("Calendar month: \(Text(MemoriesView.monthDate(key), format: Date.FormatStyle(timeZone: .gmt).month(.wide))) · \(Text("\(withMoments) days with moments", bundle: .module))", bundle: .module))
        .accessibilityIdentifier("calendar.month.\(key % 100)")
    }

    /// One dot a day, seven across: filled with moments, faint without, fainter still ahead.
    private func dots(_ key: Int) -> some View {
        let blanks = leadingBlanks(key)
        let count = daysIn(key)
        let rows = (blanks + count + 6) / 7
        let highlight = key == model.thisMonth ? ColorToken.actionCoral.color : ColorToken.textPrimary.color
        let plain = ColorToken.textPrimary.color
        return Canvas { context, _ in
            for day in 1...count {
                let slot = blanks + day - 1
                let rect = CGRect(x: CGFloat(slot % 7) * 15, y: CGFloat(slot / 7) * 15, width: 9, height: 9)
                let dayKey = key * 100 + day
                let color: Color = model.days[dayKey] != nil ? highlight : plain.opacity(dayKey > model.today ? 0.07 : 0.16)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .frame(width: 99, height: CGFloat(rows) * 15 - 6)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    // MARK: Pieces

    private func navigationRow(@ViewBuilder title: () -> some View, @ViewBuilder trailing: () -> some View) -> some View {
        ZStack {
            title()
            HStack {
                arrow(forward: false)
                Spacer()
                trailing()
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: Size.minimumTapTarget)
    }

    private func arrow(forward: Bool) -> some View {
        Button { model.step(forward ? 1 : -1) } label: {
            Icon.glyphChevron.image
                .resizable()
                .frame(width: 22, height: 22)
                .rotationEffect(forward ? .zero : .degrees(180))
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .flipsForRightToLeftLayoutDirection(true)
        .disabled(forward ? !model.canGoForward : !model.canGoBack)
        .opacity((forward ? model.canGoForward : model.canGoBack) ? 1 : 0.3)
        .accessibilityLabel(forward
            ? Text(model.scale == .month ? "Next month" : "Next year", bundle: .module)
            : Text(model.scale == .month ? "Previous month" : "Previous year", bundle: .module))
        .accessibilityIdentifier(forward ? "calendar.next" : "calendar.previous")
    }

    private func count(_ total: Int) -> Text {
        Text("\(total) moments", bundle: .module)
    }

    /// Empty slots before the 1st, counted from the region's first weekday.
    private func leadingBlanks(_ month: Int) -> Int {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .gmt
        let weekday = gregorian.component(.weekday, from: MemoriesView.monthDate(month))
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func daysIn(_ month: Int) -> Int {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .gmt
        return gregorian.range(of: .day, in: .month, for: MemoriesView.monthDate(month))?.count ?? 30
    }
}

/// Screens pushed from Memories or Today.
enum MemoriesRoute: Hashable {
    /// A day, yyyymmdd (M04).
    case day(Int)
    /// A moment among others to swipe to (M05, M06).
    case moment(MomentPager)
    /// M08.
    case search
    /// M11, M12.
    case collections
    case collection(UUID)
    /// M16, M16b.
    case recentlyDeleted
    case deletedMoment(UUID)
    /// M14.
    case onThisDay
}

extension View {
    /// Where a `MemoriesRoute` leads, for any navigation stack that can open a day or a moment.
    func memoriesDestinations(thisYear: Int) -> some View {
        navigationDestination(for: MemoriesRoute.self) { route in
            switch route {
            case let .day(day): DayScreen(day: day, thisYear: thisYear)
            case let .moment(pager): MomentViewerScreen(pager: pager)
            case .search: SearchScreen()
            case .collections: CollectionsScreen()
            case let .collection(id): CollectionScreen(id: id)
            case .recentlyDeleted: RecentlyDeletedScreen()
            case let .deletedMoment(id): DeletedMomentScreen(id: id)
            case .onThisDay: OnThisDayScreen()
            }
        }
    }
}

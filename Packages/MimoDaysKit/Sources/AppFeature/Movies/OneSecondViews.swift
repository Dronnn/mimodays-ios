import Core
import DesignSystem
import Persistence
import SwiftUI

/// P8.9 HH02: Month or Year, the period with arrows (this one and earlier ones), how many days it gives.
struct OneSecondPeriodSheet: View {
    let model: NewMovieModel
    let done: () -> Void
    @State private var period: NewMovieModel.OneSecondPeriod
    /// nil while counting; a failure offers Try again.
    @State private var count: Result<Int, any Error>?

    init(model: NewMovieModel, done: @escaping () -> Void) {
        self.model = model
        self.done = done
        _period = State(initialValue: model.oneSecondPeriod)
    }

    private var isYear: Bool { if case .year = period { true } else { false } }

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(title: Text("One second per day", bundle: .module), canFinish: (days ?? 0) > 0) {
                model.oneSecondPeriod = period
                done()
            }
            SegmentedControl(selection: Binding(get: { isYear }, set: { year in
                period = year ? .year(startYear(period)) : .month(startMonth(model.oneSecondPeriod, year: startYear(period)))
            }), options: [false, true], labelSize: 15) { year in
                year ? Text("Year", bundle: .module) : Text("Month", bundle: .module)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .accessibilityIdentifier("oneSecond.period")
            HStack {
                arrow(-1, label: isYear ? Text("Previous year", bundle: .module) : Text("Previous month", bundle: .module))
                Spacer(minLength: 8)
                Text(verbatim: period.name)
                    .textStyle(.sheetTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                arrow(1, label: isYear ? Text("Next year", bundle: .module) : Text("Next month", bundle: .module))
                    .disabled(period.shifted(by: 1).days.lowerBound > model.today)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 56)
            .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 18)
            summary.padding(.top, 22)
            Text("Each day gives one second: its first surprise, else its earliest moment. Days without moments are skipped. Hidden moments are left out.", bundle: .module)
                .textStyle(.noteMeta)
                .foregroundStyle(ColorToken.textSecondary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
                .padding(.top, 10)
            Spacer(minLength: 20)
        }
        .background(ColorToken.surfaceSheet.color.ignoresSafeArea())
        .task(id: period) { recount() }
    }

    private var days: Int? { if case let .success(days) = count { days } else { nil } }

    @ViewBuilder
    private var summary: some View {
        switch count {
        case nil:
            Text("Counting days…", bundle: .module)
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textSecondary.color)
        case let .success(days) where days == 0:
            Text("No moments to use in this period", bundle: .module)
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textSecondary.color)
                .accessibilityIdentifier("oneSecond.summary")
        case let .success(days):
            Text("\(Text("\(days) days", bundle: .module)) · \(Self.length(days))", bundle: .module)
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textLink.color)
                .accessibilityIdentifier("oneSecond.summary")
        case .failure:
            VStack(spacing: 6) {
                Text("Couldn't read this period", bundle: .module)
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Button { recount() } label: { Text("Try again", bundle: .module) }
                    .buttonStyle(.text)
                    .accessibilityIdentifier("oneSecond.tryAgain")
            }
        }
    }

    /// "27 seconds", "5 minutes, 12 seconds".
    static func length(_ days: Int) -> String {
        Duration.seconds(Double(days) * OneSecondPerDay.seconds)
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide).locale(AppLanguage.shared.locale))
    }

    private func recount() {
        count = nil
        count = Result { try model.oneSecondDays(of: period).count }
    }

    private func startYear(_ period: NewMovieModel.OneSecondPeriod) -> Int {
        switch period {
        case let .month(month): month / 100
        case let .year(year): year
        }
    }

    /// Back to Month: the month chosen before when it's in this year, else this year's last full month or December.
    private func startMonth(_ before: NewMovieModel.OneSecondPeriod, year: Int) -> Int {
        if case let .month(month) = before, month / 100 == year { return month }
        return year == model.thisYear ? model.lastMonth : year * 100 + 12
    }

    private func arrow(_ offset: Int, label: Text) -> some View {
        Button { period = period.shifted(by: offset) } label: {
            Icon.glyphChevron.image
                .resizable()
                .frame(width: 20, height: 20)
                .scaleEffect(x: offset < 0 ? -1 : 1)
                .flipsForRightToLeftLayoutDirection(true)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(offset < 0 ? "oneSecond.previous" : "oneSecond.next")
    }
}

/// HH03: the length is the days', not chosen.
struct OneSecondLengthCard: View {
    let model: NewMovieModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: OneSecondPeriodSheet.length(model.oneSecondDays.count))
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
            Text("One second a day, \(model.oneSecondPeriod.name). Set by the days.", bundle: .module)
                .textStyle(.rowCaption)
                .foregroundStyle(ColorToken.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("newMovie.oneSecondLength")
    }
}

/// HH04: each day with its moment, why that one, and Change.
struct OneSecondDaysList: View {
    let model: NewMovieModel
    @State private var changing: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.oneSecondDays, id: \.day) { day in
                if day.day != model.oneSecondDays.first?.day {
                    ColorToken.separator.color.frame(height: 1).padding(.leading, 96)
                }
                row(day)
            }
        }
        .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .sheet(item: Binding(get: { changing.map(ChangingDay.init) }, set: { changing = $0?.id })) { item in
            if let day = model.oneSecondDays.first(where: { $0.day == item.id }) {
                OneSecondDaySheet(model: model, day: day)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private struct ChangingDay: Identifiable { let id: Int }

    private func row(_ day: OneSecondPerDay.Day) -> some View {
        let item = model.items.first { $0.id == day.picked }
        return Button { changing = day.day } label: {
            HStack(spacing: 14) {
                Group {
                    if let item {
                        MemoryTile(item: item, detail: model.tiles.details[item.id], image: model.tiles.images[item.id])
                            .task { await model.tiles.load(item.id) }
                    }
                }
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MemoriesView.dayDate(day.day), format: Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day())
                        .textStyle(.rowTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                    if let item { reason(day, item) }
                    // At large type it goes under the words, which keep the row's width.
                    if dynamicTypeSize.isAccessibilitySize { change }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize { change }
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Change", bundle: .module))
        .accessibilityIdentifier("oneSecond.changeMoment")
    }

    private var change: some View {
        Text("Change", bundle: .module)
            .textStyle(.rowCaption)
            .fontWeight(.semibold)
            .foregroundStyle(ColorToken.textLink.color)
    }

    /// "First surprise · 9:12 AM", "Earliest · 8:05 AM", "Changed by you · 6:42 PM".
    private func reason(_ day: OneSecondPerDay.Day, _ item: MemoryItem) -> some View {
        let time = Text(item.capturedAt, format: OneSecondDaySheet.time(item))
        let changed = model.changedDays.contains(day.day)
        return Group {
            if changed {
                Text("Changed by you · \(time)", bundle: .module)
            } else if item.origin == .randomPrompt {
                Text("First surprise · \(time)", bundle: .module)
            } else {
                Text("Earliest · \(time)", bundle: .module)
            }
        }
        .textStyle(.rowCaption)
        .foregroundStyle((changed ? ColorToken.textLink : .textSecondary).color)
    }
}

/// HH05: the day's moments with their times; the one picked gives the day its second.
struct OneSecondDaySheet: View {
    let model: NewMovieModel
    let day: OneSecondPerDay.Day
    @State private var picked: UUID

    init(model: NewMovieModel, day: OneSecondPerDay.Day) {
        self.model = model
        self.day = day
        _picked = State(initialValue: day.picked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetBar(title: Text(MemoriesView.dayDate(day.day), format: Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day())) {
                model.choose(picked, forDay: day.day)
            }
            Text("\(Text("\(day.choices.count) moments", bundle: .module)) this day. Pick the one for its second.", bundle: .module)
                .textStyle(.noteMeta)
                .foregroundStyle(ColorToken.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.top, 8)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(day.choices, id: \.self) { id in
                        if let item = model.items.first(where: { $0.id == id }) { choice(item) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .padding(.top, 14)
            Text("Videos give their first second; you can move it in the editor.", bundle: .module)
                .textStyle(.noteMeta)
                .foregroundStyle(ColorToken.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.top, 16)
            Spacer(minLength: 16)
        }
        .background(ColorToken.surfaceSheet.color.ignoresSafeArea())
    }

    private func choice(_ item: MemoryItem) -> some View {
        let isOn = item.id == picked
        return Button { picked = item.id } label: {
            VStack(alignment: .leading, spacing: 6) {
                MemoryTile(item: item, detail: model.tiles.details[item.id], image: model.tiles.images[item.id])
                    .frame(width: 80, height: 80)
                    .overlay { SelectionMark(isOn: isOn, cornerRadius: 10) }
                    .task { await model.tiles.load(item.id) }
                Text(item.capturedAt, format: Self.time(item))
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textPrimary.color)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("oneSecond.choice")
    }

    /// The time where the moment was taken.
    static func time(_ item: MemoryItem) -> Date.FormatStyle {
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = TimeZone(identifier: item.timeZoneID) ?? .current
        return format
    }
}

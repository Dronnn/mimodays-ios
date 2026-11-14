import Core
import DesignSystem
import Persistence
import SwiftUI

/// Pages of the wizard after F02.
enum NewMovieStep: Hashable {
    case dates
    case collections
    case places
    case length
    case moments
}

/// The wizard, shown over Movies: F02 → F04 → F05, with F03 and the source lists on the way. Build makes a draft.
struct NewMovieScreen: View {
    let source: MovieSourceRule?
    let built: (UUID) -> Void
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library { NewMovieFlow(model: NewMovieModel(library: library, source: source), built: built) }
    }
}

struct NewMovieFlow: View {
    @State var model: NewMovieModel
    let built: (UUID) -> Void
    @State private var path: [NewMovieStep] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            SourceStep(model: model, path: $path, close: { dismiss() })
                .navigationDestination(for: NewMovieStep.self) { step in
                    switch step {
                    case .dates: DatesStep(model: model, path: $path)
                    case .collections: CollectionsStep(model: model)
                    case .places: PlacesStep(model: model)
                    case .length: LengthStep(model: model, path: $path)
                    case .moments:
                        MomentsStep(model: model) {
                            if let id = model.build() { built(id) }
                        }
                    }
                }
        }
        .tint(ColorToken.textLink.color)
    }
}

// MARK: - Chrome

/// `Navigation / Wizard bar`: × on the first step, ‹ and the step before on the others; "New movie" in the middle.
struct WizardBar: View {
    /// The step before ("Source", "Length"); nil shows ×.
    let back: Text?
    let action: () -> Void

    var body: some View {
        ZStack {
            Text("New movie", bundle: .module)
                .textStyle(.editorTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Button(action: action) {
                    HStack(spacing: 0) {
                        if let back {
                            Icon.glyphBack.image
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundStyle(ColorToken.textPrimary.color)
                                .flipsForRightToLeftLayoutDirection(true)
                            back
                                .textStyle(.editorCancel)
                                .foregroundStyle(ColorToken.textLink.color)
                        } else {
                            Icon.glyphClose.image
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundStyle(ColorToken.textPrimary.color)
                                .padding(.leading, 6)
                        }
                    }
                    .frame(minWidth: Size.minimumTapTarget, minHeight: Size.minimumTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(back == nil ? Text("Close", bundle: .module) : Text("Back", bundle: .module))
                .accessibilityIdentifier(back == nil ? "newMovie.close" : "newMovie.back")
                Spacer()
            }
            .padding(.leading, 10)
        }
        .frame(height: 44)
    }
}

/// `Wizard / Step n`: three hand-drawn bars, "STEP n OF 3", then the step's question.
struct WizardHeader: View {
    let step: Int
    let question: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { index in
                    Capsule()
                        .fill((index <= step ? ColorToken.actionCoral : .borderSubtle).color)
                        .frame(height: 5)
                }
            }
            .accessibilityHidden(true)
            Text("Step \(step) of 3", bundle: .module)
                .textStyle(.labelCaps)
                .foregroundStyle(ColorToken.textSecondary.color)
                .padding(.top, 11)
            question
                .textStyle(.wizardQuestion)
                .foregroundStyle(ColorToken.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 6)
                .padding(.leading, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

extension View {
    /// A wizard page: its bar on top, the canvas behind, the bottom button pinned over the home indicator.
    func wizardPage(back: Text?, action: @escaping () -> Void, @ViewBuilder bottom: () -> some View) -> some View {
        modifier(WizardPage(back: back, action: action, bottom: bottom()))
    }
}

private struct WizardPage<Bottom: View>: ViewModifier {
    let back: Text?
    let action: () -> Void
    let bottom: Bottom
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                WizardBar(back: back, action: action)
                    .background(ColorToken.canvas.color)
                    // On iPhone the bar starts where the status bar ends, as drawn (as Memories' header).
                    .padding(.top, sizeClass == .compact ? -8 : 0)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottom
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(ColorToken.canvas.color.ignoresSafeArea())
            }
            .background(ColorToken.canvas.color.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// `Button / Primary`, or `Button / Disabled` (the shape in a pale chip colour, muted words) while it can't be used.
struct WizardButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        if isEnabled {
            PrimaryButtonStyle().makeBody(configuration: configuration)
        } else {
            configuration.label
                .textStyle(.buttonPrimary)
                .foregroundStyle(ColorToken.textTertiary.color.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background { ColorToken.borderSubtle.color.mask { Icon.shapeButton.image.resizable() } }
        }
    }
}

/// A row in a wizard list card: title, detail under it, ✓ when chosen or › when it opens a page.
struct WizardRow: View {
    let title: Text
    var detail: Text?
    var isChosen = false
    var opens = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                title
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                if let detail {
                    detail
                        .textStyle(.meta)
                        .foregroundStyle(ColorToken.textSecondary.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isChosen {
                Icon.glyphCheck.image
                    .resizable()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(ColorToken.textLink.color)
                    .accessibilityHidden(true)
            } else if opens {
                Icon.glyphChevron.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// The list card the rows sit in, hairlines between them.
struct WizardCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content()) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { ColorToken.separator.color.frame(height: 1).padding(.leading, 16) }
                    row
                }
            }
        }
        .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
    }
}

// MARK: - Step 1: F02, F16

struct SourceStep: View {
    let model: NewMovieModel
    @Binding var path: [NewMovieStep]
    let close: () -> Void
    @Environment(AppRouter.self) private var router
    /// F16: the source has too few moments.
    @State private var tooFew: Bool

    init(model: NewMovieModel, path: Binding<[NewMovieStep]>, close: @escaping () -> Void, tooFew: Bool = false) {
        self.model = model
        _path = path
        self.close = close
        _tooFew = State(initialValue: tooFew)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WizardHeader(step: 1, question: Text("What's it about?", bundle: .module))
                if tooFew {
                    notEnough.padding(.top, 62)
                } else {
                    sources.padding(.top, 18)
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .wizardPage(back: nil, action: close) {
            if !tooFew {
                Button { next() } label: { Text("Next", bundle: .module) }
                    .buttonStyle(WizardButtonStyle())
                    .disabled(!model.canContinue)
                    .accessibilityIdentifier("newMovie.next")
            }
        }
        .task { model.loadChoices() }
    }

    private var sources: some View {
        WizardCard {
            period(.lastMonth, Text("Last month", bundle: .module), Text(verbatim: MoviesModel.monthTitle(model.lastMonth)))
            period(.thisYear, Text("This year", bundle: .module), Text(verbatim: String(model.thisYear)))
            period(.lastYear, Text("Last year", bundle: .module), Text(verbatim: String(model.thisYear - 1)))
            Button { open(.dates, as: .dates) } label: {
                WizardRow(
                    title: Text("Dates", bundle: .module),
                    detail: model.datesArePicked ? Text(verbatim: NewMovieModel.span(model.from!, model.to!)) : Text("Pick a start and an end", bundle: .module),
                    isChosen: model.source == .dates && model.datesArePicked, opens: !(model.source == .dates && model.datesArePicked)
                )
            }
            .accessibilityIdentifier("newMovie.source.dates")
            Button { path.append(.collections) } label: {
                WizardRow(title: Text("A collection", bundle: .module), detail: chosenCollection, isChosen: isCollection, opens: !isCollection)
            }
            .accessibilityIdentifier("newMovie.source.collection")
            Button { path.append(.places) } label: {
                WizardRow(title: Text("A place", bundle: .module), detail: chosenPlace, isChosen: isPlace, opens: !isPlace)
            }
            .accessibilityIdentifier("newMovie.source.place")
            Button { open(.moments, as: .length) } label: {
                WizardRow(title: Text("Choose moments", bundle: .module), isChosen: model.source == .moments, opens: model.source != .moments)
            }
            .accessibilityIdentifier("newMovie.source.moments")
        }
        .buttonStyle(.plain)
    }

    private func period(_ source: NewMovieModel.Source, _ title: Text, _ name: Text) -> some View {
        let count = Text("\(model.count(of: source)) moments", bundle: .module)
        return Button { model.source = source } label: {
            WizardRow(title: title, detail: Text("\(name) · \(count)", bundle: .module), isChosen: model.source == source)
        }
        .accessibilityIdentifier("newMovie.source.\(source)")
    }

    private var isCollection: Bool { if case .collection = model.source { true } else { false } }
    private var isPlace: Bool { if case .place = model.source { true } else { false } }

    private var chosenCollection: Text? {
        guard case let .collection(id) = model.source, let choice = model.collections.first(where: { $0.id == id }) else { return nil }
        return Text(verbatim: choice.title)
    }

    private var chosenPlace: Text? {
        guard isPlace else { return nil }
        return model.placeName.map { Text(verbatim: $0) } ?? Text("Unnamed place", bundle: .module)
    }

    private func open(_ source: NewMovieModel.Source, as step: NewMovieStep) {
        model.source = source
        if step == .length { next() } else { path.append(step) }
    }

    private func next() {
        if model.loadCandidates() {
            path.append(.length)
        } else {
            withAnimation(.snappy) { tooFew = true }
        }
    }

    /// F16: why not, without padding the movie; more dates or a new moment.
    private var notEnough: some View {
        VStack(spacing: 0) {
            ExplainerArt(glyph: .explainerFilm)
            Text("Not enough yet", bundle: .module)
                .textStyle(.emptyTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
            Text(
                "\(model.sourceName) has \(model.candidates.count) moments. A movie needs at least 5 so it doesn't feel stretched. We never repeat or pad clips.",
                bundle: .module
            )
            .textStyle(.emptyBody)
            .foregroundStyle(ColorToken.textBody.color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 50)
            .padding(.top, 8)
            Button {
                tooFew = false
                model.source = .dates
                path.append(.dates)
            } label: { Text("Choose more dates", bundle: .module) }
                .buttonStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .accessibilityIdentifier("newMovie.moreDates")
            Button { router.open(.capture(promptID: nil)) } label: { Text("Catch a moment now", bundle: .module) }
                .buttonStyle(.text)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .accessibilityIdentifier("newMovie.capture")
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("newMovie.tooFew")
    }
}

// MARK: - F03

struct DatesStep: View {
    @Bindable var model: NewMovieModel
    @Binding var path: [NewMovieStep]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @State private var editing: Bound
    /// yyyymm on screen.
    @State private var month: Int?

    enum Bound { case from, to }

    init(model: NewMovieModel, path: Binding<[NewMovieStep]>) {
        self.model = model
        _path = path
        // With a start picked, the end is what's left to pick (or to fix).
        _editing = State(initialValue: model.from == nil ? .from : .to)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WizardHeader(step: 1, question: Text("Which dates?", bundle: .module))
                WizardCard {
                    row(.from)
                    row(.to)
                }
                .padding(.top, 18)
                if model.datesAreReversed {
                    errorCard.padding(.top, 16)
                }
                MonthDays(month: shownMonth, chosen: [model.from, model.to].compactMap { $0 }, isError: model.datesAreReversed) { day in
                    choose(day)
                } move: { month = shift(shownMonth, by: $0) }
                    .padding(.top, model.datesAreReversed ? 24 : 24)
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .wizardPage(back: Text("Source", bundle: .module), action: { dismiss() }) {
            Button {
                if model.loadCandidates() {
                    path.append(.length)
                } else {
                    // Back to F02, which shows F16 for these dates.
                    dismiss()
                }
            } label: { Text("Next", bundle: .module) }
                .buttonStyle(WizardButtonStyle())
                .disabled(!model.datesArePicked)
                .accessibilityIdentifier("newMovie.next")
        }
        .onAppear { model.source = .dates }
    }

    private var shownMonth: Int {
        month ?? ((editing == .from ? model.from : model.to) ?? model.from ?? model.today) / 100
    }

    private func row(_ bound: Bound) -> some View {
        let key = bound == .from ? model.from : model.to
        let isError = bound == .to && model.datesAreReversed
        return Button {
            editing = bound
            if let key { month = key / 100 }
        } label: {
            HStack(spacing: 8) {
                (bound == .from ? Text("From", bundle: .module) : Text("To", bundle: .module))
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 8)
                Group {
                    if let key {
                        Text(MemoriesView.dayDate(key), format: Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
                    } else {
                        Text("Pick a day", bundle: .module)
                    }
                }
                .textStyle(isError ? .reviewRetake : .rowValue)
                .foregroundStyle((isError ? ColorToken.textDestructive : .textTertiary).color)
                Icon.glyphChevron.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(editing == bound ? .isSelected : [])
        .accessibilityIdentifier(bound == .from ? "newMovie.from" : "newMovie.to")
    }

    /// `Card / Error`: a warning on the peach shape.
    private var errorCard: some View {
        HStack(spacing: 10) {
            Icon.glyphWarning.image
                .resizable()
                .frame(width: 22, height: 22)
                .foregroundStyle(ColorToken.textLink.color)
                .accessibilityHidden(true)
            Text("The end is before the start. Pick a later end date.", bundle: .module)
                .textStyle(.infoCard)
                .foregroundStyle(ColorToken.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 16)
        .frame(minHeight: 56)
        .background { ColorToken.accentPeach.color.mask { Icon.shapeButton.image.resizable() } }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("newMovie.datesError")
    }

    private func choose(_ day: Int) {
        if editing == .from {
            model.from = day
            editing = .to
        } else {
            model.to = day
        }
    }

    private func shift(_ month: Int, by offset: Int) -> Int {
        let index = month / 100 * 12 + month % 100 - 1 + offset
        return index / 12 * 100 + index % 12 + 1
    }
}

/// F03's month: its name with ‹ ›, the weekday letters, the days; chosen days in a coral disc (dark coral when wrong).
struct MonthDays: View {
    /// yyyymm.
    let month: Int
    let chosen: [Int]
    let isError: Bool
    let choose: (Int) -> Void
    let move: (Int) -> Void
    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(MemoriesView.monthDate(month), format: Date.FormatStyle(timeZone: .gmt).month(.wide).year())
                    .textStyle(.suggestionTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                arrow(-1, label: Text("Previous month", bundle: .module))
                arrow(1, label: Text("Next month", bundle: .module))
            }
            .padding(.leading, 20)
            .padding(.trailing, 8)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, letter in
                    Text(verbatim: letter)
                        .textStyle(.labelCaps)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            LazyVGrid(columns: columns, spacing: 0) {
                // Negative ids: the days below are 1...dayCount in the same grid.
                ForEach(-leading..<0, id: \.self) { _ in Color.clear.frame(height: Size.minimumTapTarget) }
                ForEach(1...dayCount, id: \.self) { day in
                    let key = month * 100 + day
                    let isChosen = chosen.contains(key)
                    Button { choose(key) } label: {
                        Text(verbatim: "\(day)")
                            .textStyle(isChosen ? .calendarChosenDay : .calendarDay16)
                            .foregroundStyle((isChosen ? ColorToken.textOnCoral : .textPrimary).color)
                            .frame(width: 38, height: 38)
                            .background {
                                if isChosen { Circle().fill((isError && key == chosen.last ? ColorToken.textDestructive : .actionCoral).color) }
                            }
                            .frame(maxWidth: .infinity, minHeight: Size.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(MemoriesView.dayDate(key), format: Date.FormatStyle(date: .complete, time: .omitted, timeZone: .gmt)))
                    .accessibilityAddTraits(isChosen ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
    }

    private func arrow(_ offset: Int, label: Text) -> some View {
        Button { move(offset) } label: {
            Icon.glyphChevron.image
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(ColorToken.textPrimary.color)
                .rotationEffect(.degrees(offset < 0 ? 180 : 0))
                .flipsForRightToLeftLayoutDirection(true)
                .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The locale's week, first day first: "M T W T F S S".
    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var gmt: Calendar {
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = .gmt
        gmt.firstWeekday = calendar.firstWeekday
        return gmt
    }

    /// Empty cells before the 1st.
    private var leading: Int {
        let weekday = gmt.component(.weekday, from: MemoriesView.monthDate(month))
        return (weekday - gmt.firstWeekday + 7) % 7
    }

    private var dayCount: Int { gmt.range(of: .day, in: .month, for: MemoriesView.monthDate(month))?.count ?? 30 }
}

// MARK: - Source lists (no boards: F02's list card)

struct CollectionsStep: View {
    let model: NewMovieModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WizardHeader(step: 1, question: Text("Which collection?", bundle: .module))
                if model.collections.isEmpty {
                    Text("No collections yet. Make one in Memories.", bundle: .module)
                        .textStyle(.emptyBody)
                        .foregroundStyle(ColorToken.textBody.color)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                } else {
                    WizardCard {
                        ForEach(model.collections) { choice in
                            Button {
                                model.source = .collection(choice.id)
                                dismiss()
                            } label: {
                                WizardRow(
                                    title: Text(verbatim: choice.title), detail: Text("\(choice.count) moments", bundle: .module),
                                    isChosen: model.source == .collection(choice.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("newMovie.collection")
                        }
                    }
                    .padding(.top, 18)
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .wizardPage(back: Text("Source", bundle: .module), action: { dismiss() }) { EmptyView() }
    }
}

struct PlacesStep: View {
    let model: NewMovieModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WizardHeader(step: 1, question: Text("Which place?", bundle: .module))
                if model.places.isEmpty {
                    Text("No moments have a place yet.", bundle: .module)
                        .textStyle(.emptyBody)
                        .foregroundStyle(ColorToken.textBody.color)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                } else {
                    WizardCard {
                        ForEach(model.places) { place in
                            Button {
                                model.choosePlace(place)
                                dismiss()
                            } label: {
                                WizardRow(
                                    title: PlaceName.text(place), detail: Text("\(place.moments.count) moments", bundle: .module),
                                    isChosen: model.source == .place(place.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("newMovie.place")
                        }
                    }
                    .padding(.top, 18)
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .wizardPage(back: Text("Source", bundle: .module), action: { dismiss() }) { EmptyView() }
    }
}

// MARK: - Step 2: F04

struct LengthStep: View {
    @Bindable var model: NewMovieModel
    @Binding var path: [NewMovieStep]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WizardHeader(step: 2, question: Text("How long, what shape?", bundle: .module))
                section(Text("Length", bundle: .module)).padding(.top, 20)
                // A Grid, not a LazyVGrid: both cards in a row take the taller one's height.
                Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach([[MovieLength.quick, .short], [.full, .custom]], id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { length in
                                Button { model.length = length } label: { lengthOption(length) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("newMovie.length.\(length.rawValue)")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                if model.length == .custom {
                    Stepper(value: $model.customMinutes, in: 1...30) {
                        Text("\(model.customMinutes) minutes", bundle: .module)
                            .textStyle(.rowTitle)
                            .foregroundStyle(ColorToken.textPrimary.color)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .accessibilityIdentifier("newMovie.customMinutes")
                }
                section(Text("Shape", bundle: .module)).padding(.top, 24)
                HStack(spacing: 8) {
                    ForEach(MovieAspectRatio.allCases, id: \.self) { shape in
                        Button { model.aspectRatio = shape } label: { shapeOption(shape) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("newMovie.shape.\(shape.rawValue)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                Text("Photos and videos that don't match the shape", bundle: .module)
                    .textStyle(.noteMeta)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                SegmentedControl(selection: $model.fit, options: MovieFit.allCases, labelSize: 15) { fit in
                    switch fit {
                    case .fill: Text("Fill the frame", bundle: .module)
                    case .showAll: Text("Show all of it", bundle: .module)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 9)
                .accessibilityIdentifier("newMovie.fit")
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .wizardPage(back: Text("Source", bundle: .module), action: { dismiss() }) {
            Button {
                model.pickAutomatically()
                path.append(.moments)
            } label: { Text("Next", bundle: .module) }
                .buttonStyle(WizardButtonStyle())
                .accessibilityIdentifier("newMovie.next")
        }
    }

    private func section(_ text: Text) -> some View {
        text
            .textStyle(.labelCaps)
            .foregroundStyle(ColorToken.textSecondary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 22)
    }

    /// `Option / Length`: cream with a coral outline and ✓ when chosen, chip-coloured otherwise.
    private func lengthOption(_ length: MovieLength) -> some View {
        let isOn = model.length == length
        return VStack(alignment: .leading, spacing: 4) {
            Group {
                switch length {
                case .quick: Text("Quick", bundle: .module)
                case .short: Text("Short", bundle: .module)
                case .full: Text("Full", bundle: .module)
                case .custom: Text("Custom", bundle: .module)
                }
            }
            .textStyle(.rowTitle)
            .foregroundStyle(ColorToken.textPrimary.color)
            Group {
                switch length {
                case .quick: Text("about 1 min", bundle: .module)
                case .short: Text("3 to 5 min", bundle: .module)
                case .full:
                    let total = Duration.seconds(model.fullSeconds.rounded()).formatted(.time(pattern: .minuteSecond))
                    Text("every moment · \(total)", bundle: .module)
                case .custom: Text("you choose", bundle: .module)
                }
            }
            .textStyle(.rowCaption)
            .foregroundStyle(ColorToken.textSecondary.color)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, minHeight: 66, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if isOn {
                Icon.glyphCheck.image
                    .resizable()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(ColorToken.textLink.color)
                    .padding(12)
                    .accessibilityHidden(true)
            }
        }
        .background(option(isOn))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// `Option / Shape`: a little frame of the shape over its name.
    private func shapeOption(_ shape: MovieAspectRatio) -> some View {
        let isOn = model.aspectRatio == shape
        let size: CGSize = switch shape {
        case .portrait9x16: CGSize(width: 36, height: 64)
        case .landscape16x9: CGSize(width: 74, height: 42)
        case .square1x1: CGSize(width: 52, height: 52)
        }
        return VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOn ? Color(hex: 0xC9B8AA) : Color(hex: 0xD5C3B4))
                .frame(width: size.width, height: size.height)
                .frame(height: 64)
                .padding(.top, 14)
                .accessibilityHidden(true)
            Group {
                switch shape {
                case .portrait9x16: Text("9:16 · Phone", bundle: .module)
                case .landscape16x9: Text("16:9 · TV", bundle: .module)
                case .square1x1: Text("1:1 · Square", bundle: .module)
                }
            }
            .textStyle(isOn ? .shapeLabelOn : .rowCaption)
            .foregroundStyle((isOn ? ColorToken.textPrimary : .textSecondary).color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .top)
        .background(option(isOn))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func option(_ isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill((isOn ? ColorToken.surfaceCard : .surfaceChip).color)
            .strokeBorder(isOn ? ColorToken.actionCoral.color : .clear, lineWidth: 2)
    }
}

// MARK: - Step 3: F05

struct MomentsStep: View {
    let model: NewMovieModel
    let build: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsAll = true

    var body: some View {
        let shown = showsAll ? model.items : model.items.filter { model.picked.contains($0.id) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WizardHeader(step: 3, question: Text("Which moments?", bundle: .module))
                intro
                    .textStyle(.pageIntro)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                SegmentedControl(selection: $showsAll, options: [false, true], labelSize: 15) { all in
                    all ? Text("All · \(model.items.count)", bundle: .module) : Text("Picked · \(model.picked.count)", bundle: .module)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .accessibilityIdentifier("newMovie.picked")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(shown) { item in
                        let isOn = model.picked.contains(item.id)
                        Button { model.toggle(item.id) } label: {
                            MemoryTile(item: item, detail: model.tiles.details[item.id], image: model.tiles.images[item.id], videoBadgeAtTop: true)
                                .overlay { SelectionMark(isOn: isOn, cornerRadius: 10) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                        .accessibilityIdentifier("newMovie.moment")
                        .task { await model.tiles.load(item.id) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .wizardPage(back: Text("Length", bundle: .module), action: { dismiss() }) {
            Button(action: build) { Text("Build the movie", bundle: .module) }
                .buttonStyle(WizardButtonStyle())
                .disabled(!model.canBuild)
                .accessibilityIdentifier("newMovie.build")
        }
    }

    private var intro: Text {
        if model.source == .moments, model.presetIDs.isEmpty {
            Text("Tap the moments you want in the movie. It needs at least 5.", bundle: .module)
        } else {
            Text("We picked \(model.picked.count) of \(model.items.count), spread evenly across \(model.periodName). Tap to add or remove.", bundle: .module)
        }
    }
}

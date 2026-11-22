import Core
import DesignSystem
import Observation
import Persistence
import SwiftData
import SwiftUI

/// P3.5 X04/X04b: which videos, the new size, and what they'd take after.
@MainActor
@Observable
final class ShrinkModel {
    enum Which: Hashable, CaseIterable {
        case month
        case year
        case all
        case chosen

        var label: Text {
            switch self {
            case .month: Text("30+ days", bundle: .module, comment: "Make videos smaller (X04): videos older than 30 days")
            case .year: Text("1+ year", bundle: .module, comment: "Make videos smaller (X04): videos older than a year")
            case .all: Text("All", bundle: .module)
            case .chosen: Text("Choose…", bundle: .module, comment: "Make videos smaller (X04): pick the videos one by one")
            }
        }
    }

    /// X04b: one video to tick, with what its cameras take now.
    struct Choice: Identifiable, Equatable {
        var item: MemoryItem
        var bytes: Int64
        var thumbnailPath: String?
        var id: UUID { item.id }
    }

    var which = Which.month { didSet { refresh() } }
    var size = VideoSize.balanced { didSet { refresh() } }
    var chosen: Set<UUID> = [] { didSet { refresh() } }
    private(set) var candidates: [ShrinkCandidate] = []
    private(set) var images: [UUID: UIImage] = [:]
    let library: MediaLibrary
    private let now: () -> Date

    init(library: MediaLibrary, now: @escaping () -> Date = Date.init) {
        self.library = library
        self.now = now
        refresh()
    }

    var selection: ShrinkSelection {
        switch which {
        case .month: .olderThan30Days
        case .year: .olderThanAYear
        case .all: .all
        case .chosen: .chosen(chosen)
        }
    }

    var bytesNow: Int64 { candidates.reduce(0) { $0 + $1.bytes } }
    var bytesAfter: Int64 { candidates.reduce(0) { $0 + $1.estimatedBytes(at: size) } }
    var frees: Int64 { bytesNow - bytesAfter }

    func refresh() {
        candidates = (try? ShrinkPolicy.candidates(selection, size: size, in: library.context, now: now())) ?? []
    }

    /// X04b: every video that would get smaller at this size, newest day first, by day.
    func choices() -> [(day: Int, choices: [Choice])] {
        let all = (try? ShrinkPolicy.candidates(.all, size: size, in: library.context, now: now())) ?? []
        let bytes = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.bytes) })
        let ids = Set(bytes.keys)
        let video = MediaType.video.rawValue
        let descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate { $0.mediaTypeRaw == video && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let choices = ((try? library.context.fetch(descriptor)) ?? []).filter { ids.contains($0.id) }.map {
            Choice(
                item: MemoryItem(
                    id: $0.id, localDay: $0.localDay, capturedAt: $0.capturedAt, timeZoneID: $0.timeZoneID,
                    mediaType: $0.mediaType, origin: $0.origin, isFavorite: $0.isFavorite
                ),
                bytes: bytes[$0.id] ?? 0,
                thumbnailPath: $0.media.first { $0.role == .thumbnail }?.relativePath
            )
        }
        var days: [(day: Int, choices: [Choice])] = []
        for choice in choices {
            if days.last?.day == choice.item.localDay { days[days.count - 1].choices.append(choice) } else { days.append((choice.item.localDay, [choice])) }
        }
        return days
    }

    func load(_ choice: Choice, pixels: Int = MemoriesModel.tilePixels) async {
        guard images[choice.id] == nil, let path = choice.thumbnailPath, let url = try? library.store.url(for: path),
              let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: pixels) else { return }
        images[choice.id] = UIImage(cgImage: image)
    }

    var today: Date { now() }
}

struct ShrinkScreen: View {
    @Environment(\.mediaLibrary) private var library
    @Environment(ShrinkRun.self) private var run: ShrinkRun?

    var body: some View {
        if let library, let run {
            ModelHost({ ShrinkModel(library: library) }) { ShrinkHost(model: $0, run: run) }
        }
    }
}

private struct ShrinkHost: View {
    @State var model: ShrinkModel
    let run: ShrinkRun
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch run.phase {
            case .idle: ShrinkView(model: model) { run.start(model.selection, size: model.size) }
            case .running, .waiting, .finished: ShrinkProgressView(run: run) { model.refresh() }
            }
        }
        .environment(\.shrinkBack, { dismiss() })
    }
}

extension EnvironmentValues {
    @Entry var shrinkBack: () -> Void = {}
}

/// X04.
struct ShrinkView: View {
    @Bindable var model: ShrinkModel
    let start: () -> Void
    @State private var choosing = false
    /// What Which videos showed before Choose…, for a Cancel.
    @State private var before = ShrinkModel.Which.month
    @Environment(\.shrinkBack) private var back

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Storage", bundle: .module), action: back)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Make videos smaller", bundle: .module)
                        .textStyle(.pageTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    Text("Older videos are made again at a smaller size. Both cameras of a moment stay together, and nothing else about the moment changes.", bundle: .module)
                        .textStyle(.pageIntro)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    sectionLabel(Text("Which videos", bundle: .module)).padding(.top, 18)
                    SegmentedControl(selection: whichBinding, options: ShrinkModel.Which.allCases, fitsLabels: true) { $0.label }
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("shrink.which")
                    sectionLabel(Text("New size", bundle: .module)).padding(.top, 18)
                    SegmentedControl(selection: $model.size, options: [VideoSize.balanced, .compact]) { $0.label }
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("shrink.size")
                    summary
                        .padding(.horizontal, 16)
                        .padding(.top, 28)
                    DataNote(text: Text("Each original is replaced only after its smaller copy is checked. You can keep using MimoDays; it goes on after a restart.", bundle: .module))
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                }
                .padding(.bottom, 24)
            }
            Button(action: start) { Text("Make smaller", bundle: .module, comment: "Make videos smaller (X04): starts the run") }
                .buttonStyle(.primary)
                .disabled(model.candidates.isEmpty)
                .accessibilityIdentifier("shrink.start")
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .sheet(isPresented: $choosing) {
            ShrinkChooser(model: model, chosen: model.chosen) { picked in
                choosing = false
                if let picked {
                    model.chosen = picked
                } else if model.chosen.isEmpty {
                    model.which = before
                }
            }
        }
    }

    /// Choose… opens X04b each time it's picked.
    private var whichBinding: Binding<ShrinkModel.Which> {
        Binding {
            model.which
        } set: { value in
            if value == .chosen {
                if model.which != .chosen { before = model.which }
                choosing = true
            }
            model.which = value
        }
    }

    private var summary: some View {
        DataCard {
            if model.candidates.isEmpty {
                Text("No videos here need it: they're already this small.", bundle: .module)
                    .textStyle(.rowDetail)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .accessibilityIdentifier("shrink.nothing")
            } else {
                summaryRow(Text("\(Text("\(model.candidates.count) videos", bundle: .module)) now", bundle: .module, comment: "Make videos smaller (X04): e.g. 142 videos now, next to their size"), value: Text(StorageView.bytes(model.bytesNow)))
                summaryRow(Text("After", bundle: .module, comment: "Make videos smaller (X04): what the videos take after"), value: about(model.bytesAfter))
                summaryRow(Text("Frees", bundle: .module, comment: "Make videos smaller (X04): the space it frees"), value: about(model.frees))
            }
        }
        .accessibilityIdentifier("shrink.summary")
    }

    private func about(_ bytes: Int64) -> Text {
        Text("about \(StorageView.bytes(bytes))", bundle: .module, comment: "Make videos smaller (X04): an estimated size, e.g. about 1.3 GB")
    }

    private func summaryRow(_ title: Text, value: Text) -> some View {
        HStack {
            title.textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
            Spacer(minLength: 8)
            value.textStyle(.rowValue).foregroundStyle(ColorToken.textTertiary.color)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 8)
        .frame(minHeight: 32)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func sectionLabel(_ text: Text) -> some View {
        text.textStyle(.labelCaps)
            .foregroundStyle(ColorToken.textSecondary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 22)
    }
}

/// X04b: the videos to make smaller, by day, with their sizes.
struct ShrinkChooser: View {
    let model: ShrinkModel
    @State var chosen: Set<UUID>
    /// Nil on Cancel.
    let close: (Set<UUID>?) -> Void
    @State private var days: [(day: Int, choices: [ShrinkModel.Choice])] = []

    var body: some View {
        let all = days.flatMap(\.choices)
        let picked = all.filter { chosen.contains($0.id) }
        VStack(spacing: 0) {
            TitleBar {
                Button { close(nil) } label: {
                    Text("Cancel", bundle: .module).textStyle(.editorCancel).foregroundStyle(ColorToken.textPrimary.color)
                }
                .accessibilityIdentifier("shrinkChooser.cancel")
            } title: {
                count(picked)
                    .textStyle(.editorTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("shrinkChooser.count")
            } trailing: {
                Button { chosen = Set(all.map(\.id)) } label: {
                    Text("All", bundle: .module).textStyle(.editorDone).foregroundStyle(ColorToken.textLink.color)
                }
                .accessibilityIdentifier("shrinkChooser.all")
            }
            .buttonStyle(.plain)
            .frame(minHeight: Size.minimumTapTarget)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(days, id: \.day) { day in
                        Text("\(MemoriesView.dayLabel(day.day, now: model.today, calendar: .current)) · \(count(day.choices))", bundle: .module)
                            .textStyle(.labelCaps)
                            .foregroundStyle(ColorToken.textSecondary.color)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, 22)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                            ForEach(day.choices) { choice in
                                SelectableTile(selection: selectionBinding, id: choice.id, shape: StripTile.shape(choice.item.capturedAt)) {
                                    MemoryTile(item: choice.item, detail: nil, image: model.images[choice.id], leavesRoomForMark: true)
                                        .overlay(alignment: .bottomLeading) { SizeBadge(bytes: choice.bytes).padding(7) }
                                }
                                .accessibilityIdentifier("shrinkChooser.tile")
                                .task { await model.load(choice) }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 16)
            }
            Button { close(chosen) } label: { Text("Done", bundle: .module) }
                .buttonStyle(.primary)
                .disabled(chosen.isEmpty)
                .accessibilityIdentifier("shrinkChooser.done")
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .onAppear { days = model.choices() }
    }

    private var selectionBinding: Binding<Set<UUID>?> {
        Binding { chosen } set: { chosen = $0 ?? [] }
    }

    /// "3 videos · 404 MB".
    private func count(_ choices: [ShrinkModel.Choice]) -> Text {
        let bytes = choices.reduce(Int64(0)) { $0 + $1.bytes }
        return Text("\(Text("\(choices.count) videos", bundle: .module)) · \(StorageView.bytes(bytes))", bundle: .module)
    }
}

/// X04b: what a video's cameras take now, on its tile.
struct SizeBadge: View {
    let bytes: Int64

    var body: some View {
        Text(StorageView.bytes(bytes))
            .textStyle(.tileBadge)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(ColorToken.mediaScrim.color))
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// X05: how far it got, while it runs and once it's done.
struct ShrinkProgressView: View {
    let run: ShrinkRun
    /// After Done: X04 counts again.
    let done: () -> Void
    @Environment(\.shrinkBack) private var back

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Storage", bundle: .module), action: back)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    title
                        .textStyle(.pageTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    status
                        .textStyle(.meta)
                        .foregroundStyle(ColorToken.textBody.color)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .accessibilityIdentifier("shrink.status")
                    bar
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .accessibilityElement()
                        .accessibilityLabel(Text("Progress", bundle: .module))
                        .accessibilityValue(counted)
                    DataNote(text: note)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    Group {
                        if case .finished = run.phase {
                            Button {
                                run.acknowledge()
                                done()
                            } label: { Text("Done", bundle: .module) }
                                .accessibilityIdentifier("shrink.done")
                        } else {
                            Button { run.stop() } label: { Text("Stop", bundle: .module) }
                                .accessibilityIdentifier("shrink.stop")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                }
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private var progress: (done: Int, total: Int, freed: Int64) {
        if case let .finished(outcome) = run.phase { return (outcome.done + outcome.skipped, outcome.total, outcome.freed) }
        guard let job = run.job else { return (0, 0, 0) }
        return (job.total - job.remaining.count, job.total, job.freed)
    }

    private var title: Text {
        guard case let .finished(outcome) = run.phase else { return Text("Making videos smaller", bundle: .module) }
        if outcome.stopped || outcome.stoppedForSpace { return Text("Stopped", bundle: .module, comment: "Make videos smaller (X05): the run was stopped") }
        return Text("Videos made smaller", bundle: .module)
    }

    /// "37 of 142 videos".
    private var counted: Text {
        let progress = progress
        return Text("\(progress.done) of \(Text("\(progress.total) videos", bundle: .module))", bundle: .module, comment: "Make videos smaller (X05): e.g. 37 of 142 videos")
    }

    private var status: Text {
        let freed = StorageView.bytes(progress.freed)
        if case .finished = run.phase {
            return Text("\(counted) · \(Text("\(freed) freed", bundle: .module, comment: "Make videos smaller (X05): the space freed in the end"))", bundle: .module)
        }
        return Text("\(counted) · \(Text("\(freed) freed so far", bundle: .module, comment: "Make videos smaller (X05): the space freed while it runs"))", bundle: .module)
    }

    private var note: Text {
        switch run.phase {
        case let .finished(outcome) where outcome.stoppedForSpace:
            Text("There isn't enough free space for the next video. Free some space, then start again.", bundle: .module)
        case let .finished(outcome) where outcome.skipped > 0:
            Text("Some videos stayed as they were: their smaller copies didn't pass the check.", bundle: .module)
        case .finished:
            Text("Each original was replaced only after its smaller copy was checked.", bundle: .module)
        case .waiting:
            Text("Waiting for a backup or an export to finish: they use these files.", bundle: .module)
        case .idle, .running:
            Text("You can leave this screen or close MimoDays. It goes on next time, from the video it stopped at.", bundle: .module)
        }
    }

    private var bar: some View {
        let progress = progress
        let fraction = progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ColorToken.surfaceChip.color)
                Capsule().fill(ColorToken.actionCoral.color).frame(width: max(proxy.size.width * fraction, fraction > 0 ? 14 : 0))
            }
        }
        .frame(height: 14)
    }
}

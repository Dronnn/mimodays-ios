import AppIntents
import SwiftUI
import WidgetFeature
import WidgetKit

/// The widgets read only the shelf the app writes; the gallery shows the plain tiles, never a memory.
private var shelf: WidgetShelf? { WidgetShelf.shared }

/// Before the app has written anything, the iPhone's own language.
private func language(_ payload: WidgetPayload?) -> String {
    payload?.language ?? Locale.current.language.languageCode?.identifier ?? "en"
}

private func picture(_ name: String?, in payload: WidgetPayload?) -> UIImage? {
    guard let name, payload?.showsPhotos == true else { return nil }
    return shelf?.image(name)
}

// MARK: On this day

struct OnThisDayEntry: TimelineEntry {
    let date: Date
    let payload: WidgetPayload?
}

/// The app works out a week ahead; the widget turns the page at each midnight.
struct OnThisDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> OnThisDayEntry {
        OnThisDayEntry(date: .now, payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (OnThisDayEntry) -> Void) {
        completion(OnThisDayEntry(date: .now, payload: context.isPreview ? nil : shelf?.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OnThisDayEntry>) -> Void) {
        let payload = shelf?.read()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let midnights = (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let entries = [OnThisDayEntry(date: .now, payload: payload)] + midnights.map { OnThisDayEntry(date: $0, payload: payload) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct OnThisDayEntryView: View {
    let entry: OnThisDayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let content = WidgetContent.onThisDay(entry.payload, today: WidgetContent.dayKey(entry.date, calendar: .current))
        let image: UIImage? = if case let .memory(day) = content { picture(day.cover.image, in: entry.payload) } else { nil }
        OnThisDayWidgetView(content: content, isMedium: family == .systemMedium, image: image)
            .widgetLanguage(language(entry.payload))
            .widgetCard()
    }
}

struct OnThisDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnThisDay", provider: OnThisDayProvider()) { OnThisDayEntryView(entry: $0) }
            .configurationDisplayName(Text(WidgetText.onThisDay))
            .description(Text(WidgetText.onThisDayDescription))
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

// MARK: Random memory

struct RandomMemoryEntry: TimelineEntry {
    let date: Date
    let payload: WidgetPayload?
    let pick: UUID?
}

/// Changes only when the app writes or Another picks: no schedule of its own.
struct RandomMemoryProvider: TimelineProvider {
    func placeholder(in context: Context) -> RandomMemoryEntry {
        RandomMemoryEntry(date: .now, payload: nil, pick: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RandomMemoryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RandomMemoryEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> RandomMemoryEntry {
        RandomMemoryEntry(date: .now, payload: shelf?.read(), pick: shelf?.pick)
    }
}

struct RandomMemoryEntryView: View {
    let entry: RandomMemoryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let content = WidgetContent.random(entry.payload, pick: entry.pick)
        let shown: WidgetPayload.Memory? = if case let .memory(memory, _) = content { memory } else { nil }
        RandomMemoryWidgetView(
            content: content, isMedium: family == .systemMedium, showsPhotos: entry.payload?.showsPhotos == true,
            image: picture(shown?.image, in: entry.payload)
        ) { label in
            AnyView(Button(intent: AnotherMemoryIntent(current: shown?.id)) { label }.buttonStyle(.plain))
        }
        .widgetLanguage(language(entry.payload))
        .widgetCard()
    }
}

struct RandomMemoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RandomMemory", provider: RandomMemoryProvider()) { RandomMemoryEntryView(entry: $0) }
            .configurationDisplayName(Text(WidgetText.randomMemory))
            .description(Text(WidgetText.randomMemoryDescription))
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

/// Another: a different memory from the pool, kept on the shelf until the app writes a new pool.
struct AnotherMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Another memory"
    static let isDiscoverable = false

    @Parameter(title: "Memory on show")
    var current: String?

    init() {}

    init(current: UUID?) {
        self.current = current?.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let shelf, let payload = shelf.read(), !payload.isLocked else { return .result() }
        var generator = SystemRandomNumberGenerator()
        shelf.pick = WidgetContent.another(after: current.flatMap(UUID.init(uuidString:)), in: payload.random, using: &generator)
        return .result()
    }
}

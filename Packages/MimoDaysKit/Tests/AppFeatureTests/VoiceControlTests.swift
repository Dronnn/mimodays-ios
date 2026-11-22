@testable import AppFeature
@testable import Core
import Persistence
import SwiftUI
import Testing
import TestSupport
import UIKit

/// P4.4 (V4): what Voice Control hears, read from the accessibility tree iOS builds for the view: the words a
/// control answers to (V2) and the named actions that stand in for gestures (V3).
@MainActor
struct VoiceControlTests {
    struct Node {
        var label: String
        var inputLabels: [String]
        var actions: [String]
    }

    /// SwiftUI builds the tree only while assistive tech is on: turn it on for this process, as the system does.
    private static let accessibilityOn: Void = {
        guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(library, "_AXSApplicationAccessibilitySetEnabled") else { return }
        unsafeBitCast(symbol, to: (@convention(c) (Bool) -> Void).self)(true)
    }()

    /// Every element of `view` as iOS presents it to assistive tech, laid out on an iPhone-sized window.
    private func nodes(_ view: some View) -> [Node] {
        Self.accessibilityOn
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: "en_US")))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        _ = host.view.accessibilityElements
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        defer { window.isHidden = true }
        var found: [Node] = []
        func walk(_ element: NSObject) {
            if element.isAccessibilityElement {
                found.append(Node(
                    label: element.accessibilityLabel ?? "",
                    inputLabels: element.accessibilityUserInputLabels ?? [],
                    actions: (element.accessibilityCustomActions ?? []).map(\.name)
                ))
            }
            let children = element.accessibilityElements as? [NSObject]
                ?? (0 ..< max(element.accessibilityElementCount(), 0)).compactMap { element.accessibilityElement(at: $0) as? NSObject }
            children.forEach(walk)
            if let view = element as? UIView { view.subviews.forEach(walk) }
        }
        walk(host.view)
        return found
    }

    /// P4.2: the letter shown, then the day's name.
    @Test func weekdaysAnswerToTheLetterShownThenTheName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let found = nodes(WeekdayPicker(schedule: .constant(ReminderSchedule())).environment(\.calendar, calendar))
        #expect(found.first { $0.label == "Monday" }?.inputLabels == ["M", "Monday"])
        #expect(found.filter { !$0.inputLabels.isEmpty }.count == 7)
    }

    /// P4.3: the picture's tap and long press by name (the pinch is VoiceOver's zoom).
    @Test func theCameraPictureNamesItsGestures() async {
        let engine = SimulatedCaptureEngine()
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(CameraSettings()), isSurprise: false,
            microphoneStatus: { .granted }, onCapture: { _ in }
        )
        await model.start()
        let picture = nodes(InteractivePreview(model: model, position: .back)).first { $0.label == "Back camera" }
        #expect(Set(picture?.actions ?? []) == ["Focus in the middle", "Lock focus and exposure"])
    }

    /// rev-library: a card offers only what it can do: no Swap on one camera, no Previous on the first moment.
    @Test func aCardOffersOnlyTheActionsItCanRun() {
        let card = Color.orange.frame(width: 300, height: 400)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "Card"))
            .memoryCardActions(MemoryCardActions(flip: {}, swap: nil, step: { _ in }, canStep: { $0 > 0 }))
        #expect(Set(nodes(card).first { $0.label == "Card" }?.actions ?? []) == ["Flip card", "Next moment"])
        let both = Color.orange.frame(width: 300, height: 400)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "Card"))
            .memoryCardActions(MemoryCardActions(flip: {}, swap: {}, step: { _ in }))
        #expect(Set(nodes(both).first { $0.label == "Card" }?.actions ?? []) == ["Flip card", "Swap cameras", "Next moment", "Previous moment"])
    }

    /// P4.3: the selfie window's drag, pinch and press come down to one named action, which opens its sheet.
    @Test func theSelfieWindowNamesItsAdjustment() {
        let window = nodes(AdjustableSelfieWindow(
            placement: .constant(CameraSettings.SelfieWindow()), showsSheet: .constant(false),
            layout: SelfieWindowLayout(preview: CGSize(width: 402, height: 700), topInset: 62), id: "selfie"
        ) { Color.gray }).first { $0.label == "Selfie window" }
        #expect(window?.actions == ["Adjust selfie window"])
    }

    /// P4.2: a calendar day answers to the number shown or its date, a month to its short or full name.
    @Test func calendarDaysAndMonthsAnswerToTheWordsShown() throws {
        let container = try TestStore.container()
        let store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Voice-\(UUID().uuidString)"))
        let clock = TestDateProvider()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        clock.set(utc.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!)
        let model = MemoriesModel(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline(), clock: clock, calendar: { utc })
        model.refresh()
        model.mode = .calendar
        let month = nodes(MemoriesCalendarView(model: model).environment(\.calendar, utc).environment(AppRouter()))
        let eleventh = month.first { $0.inputLabels.first == "11" }
        #expect(eleventh?.inputLabels == ["11", "November 11"], "\(month.map(\.inputLabels))")
        model.zoomOut()
        let year = nodes(MemoriesCalendarView(model: model).environment(\.calendar, utc).environment(AppRouter()))
        #expect(year.contains { $0.inputLabels == ["Nov", "November"] }, "\(year.map(\.inputLabels))")
    }
}

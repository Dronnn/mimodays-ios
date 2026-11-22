import Foundation
import Testing
@testable import WidgetFeature

@Suite struct WidgetContentTests {
    let a = WidgetPayload.Memory(id: UUID(), day: 20_251_121, place: "Yerevan", kind: .photo, image: "a.jpg")
    let b = WidgetPayload.Memory(id: UUID(), day: 20_250_308, place: nil, kind: .video)
    let c = WidgetPayload.Memory(id: UUID(), day: 20_240_101, place: nil, kind: .text)

    private func payload(locked: Bool = false, random: [WidgetPayload.Memory]? = nil) -> WidgetPayload {
        WidgetPayload(
            isLocked: locked, showsPhotos: true, language: "en", firstDay: 20_261_122, lastDay: 20_261_128,
            onThisDay: [WidgetPayload.Day(today: 20_261_122, count: 3, cover: a)], random: random ?? [a, b, c]
        )
    }

    @Test func nothingWrittenYetShowsThePlainTile() {
        #expect(WidgetContent.onThisDay(nil, today: 20_261_122) == .placeholder)
        #expect(WidgetContent.random(nil, pick: nil) == .placeholder)
    }

    @Test func appLockShowsNothingPrivate() {
        #expect(WidgetContent.onThisDay(payload(locked: true), today: 20_261_122) == .locked)
        #expect(WidgetContent.random(payload(locked: true), pick: a.id) == .locked)
        #expect(WidgetPayload.locked(language: "en").images.isEmpty)
    }

    @Test func onThisDayFollowsTheDay() {
        let payload = payload()
        #expect(WidgetContent.onThisDay(payload, today: 20_261_122) == .memory(payload.onThisDay[0]))
        #expect(WidgetContent.onThisDay(payload, today: 20_261_123) == .empty)
        // A day the app hasn't worked out: no guess.
        #expect(WidgetContent.onThisDay(payload, today: 20_261_129) == .placeholder)
    }

    @Test func randomShowsThePickOrTheFirst() {
        let payload = payload()
        #expect(WidgetContent.random(payload, pick: b.id) == .memory(b, canSwap: true))
        #expect(WidgetContent.random(payload, pick: UUID()) == .memory(a, canSwap: true))
        #expect(WidgetContent.random(self.payload(random: [c]), pick: nil) == .memory(c, canSwap: false))
        #expect(WidgetContent.random(self.payload(random: []), pick: nil) == .empty)
    }

    @Test func anotherNeverRepeatsTheOneOnShow() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let next = WidgetContent.another(after: a.id, in: [a, b, c], using: &generator)
            #expect(next != nil && next != a.id)
        }
        #expect(WidgetContent.another(after: a.id, in: [a], using: &generator) == a.id)
    }

    @Test func dayKeysRoundTrip() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Yerevan")!
        let date = WidgetContent.date(ofDay: 20_250_308, calendar: calendar)
        #expect(WidgetContent.dayKey(date, calendar: calendar) == 20_250_308)
    }
}

@Suite struct WidgetShelfTests {
    private func shelf() -> WidgetShelf {
        WidgetShelf(directory: FileManager.default.temporaryDirectory.appending(path: "shelf-\(UUID().uuidString)"))
    }

    @Test func writesReadsAndDropsPicturesNoLongerNamed() throws {
        let shelf = shelf()
        defer { shelf.purge() }
        let memory = WidgetPayload.Memory(id: UUID(), day: 20_251_121, place: nil, kind: .photo, image: "one.jpg")
        let first = WidgetPayload(language: "de", firstDay: 1, lastDay: 2, random: [memory])
        try shelf.write(first, images: ["one.jpg": Data([1]), "stray.jpg": Data([2])])
        #expect(shelf.read() == first)
        #expect(shelf.imageNames == ["one.jpg"])

        var second = first
        second.random = [WidgetPayload.Memory(id: UUID(), day: 1, place: nil, kind: .photo, image: "two.jpg")]
        try shelf.write(second, images: ["two.jpg": Data([3])])
        #expect(shelf.imageNames == ["two.jpg"])
    }

    @Test func purgeEmptiesEverything() throws {
        let shelf = shelf()
        try shelf.write(WidgetPayload(language: "en"), images: [:])
        shelf.pick = UUID()
        shelf.purge()
        #expect(shelf.read() == nil)
        #expect(shelf.pick == nil)
    }

    @Test func keepsThePick() {
        let shelf = shelf()
        defer { shelf.purge() }
        let id = UUID()
        shelf.pick = id
        #expect(shelf.pick == id)
        shelf.pick = nil
        #expect(shelf.pick == nil)
    }
}

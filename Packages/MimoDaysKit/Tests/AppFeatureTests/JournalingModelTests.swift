@testable import AppFeature
import Core
import Foundation
import Testing

/// P8.12: the suggestion picked in Apple's picker, through a stand-in for the picker.
@MainActor
struct JournalingModelTests {
    private struct Unreadable: Error {}

    private func model(_ pick: @escaping @MainActor () throws -> JournalingPick) async -> JournalingModel {
        let model = JournalingModel(load: pick)
        await model.start()
        return model
    }

    @Test func aSuggestionThatCantBeReadOffersTryAgain() async {
        var fails = true
        let model = JournalingModel {
            if fails { throw Unreadable() }
            return try LaunchConfiguration.JournalingFixture.prompt.pick()
        }
        await model.start()
        #expect(model.phase == .failed && model.next == nil)
        fails = false
        await model.start()
        #expect(model.phase == .ready && model.use == .prompt)
    }

    /// Nothing in it, or only what MimoDays doesn't take (a workout): nothing to add.
    @Test(arguments: [JournalingPick(title: "Empty"), try! LaunchConfiguration.JournalingFixture.nothing.pick()])
    func nothingUsableHasNothingToAdd(pick: JournalingPick) async {
        let model = await model { pick }
        #expect(model.phase == .unsupported && model.next == nil)
    }

    /// Several photos: none chosen until one is tapped.
    @Test func severalPhotosWaitForOneToBeChosen() async throws {
        let pick = try LaunchConfiguration.JournalingFixture.photos.pick()
        let model = await model { pick }
        #expect(model.phase == .ready && model.thumbnails.count == 3)
        #expect(model.chosen == nil && !model.canContinue && model.next == nil)
        model.chosen = 2
        #expect(model.next == .importPhoto(pick.photos[2]))
    }

    @Test func oneUsablePhotoIsChosenAlready() async throws {
        var pick = try LaunchConfiguration.JournalingFixture.photos.pick()
        // One that doesn't open as a picture is left out.
        pick.photos[1].url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).jpg")
        pick.photos.removeLast()
        let model = await model { pick }
        #expect(model.pick?.photos == [pick.photos[0]])
        #expect(model.next == .importPhoto(pick.photos[0]))
    }

    @Test func photosThatDontOpenCantBeAdded() async {
        let missing = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).jpg")
        let model = await model { JournalingPick(title: "Gone", photos: [.init(url: missing, date: nil)]) }
        #expect(model.phase == .failed)
    }

    @Test func aPromptOpensWriteAMoment() async {
        let model = await model { JournalingPick(title: "Reflection", prompts: ["  ", " What made you smile today? "]) }
        #expect(model.use == .prompt && !model.offersBoth)
        #expect(model.next == .write(prompt: "What made you smile today?"))
    }

    /// Photos and a prompt: a photo first, the prompt one tap away.
    @Test func photosAndAPromptOfferBoth() async throws {
        let pick = try LaunchConfiguration.JournalingFixture.both.pick()
        let model = await model { pick }
        #expect(model.offersBoth && model.use == .photo && model.next == nil)
        model.use = .prompt
        #expect(model.next == .write(prompt: "What made you smile today?"))
    }

    /// A photo without a date of its own is dated by the suggestion; without either, by when it's imported.
    @Test func aPhotoWithoutItsOwnDateTakesTheSuggestions() async throws {
        let pick = try LaunchConfiguration.JournalingFixture.photos.pick()
        let dated = try #require(await JournalingPhotoItem(photo: pick.photos[0]).loadFile())
        let read = try #require(await PhotoImportModel.read(dated, id: 0))
        #expect(read.capturedAt.instant == pick.photos[0].date)
        let undated = try #require(await JournalingPhotoItem(photo: pick.photos[1]).loadFile())
        let now = Date()
        let fallback = try #require(await PhotoImportModel.read(undated, id: 1))
        #expect(abs(fallback.capturedAt.instant.timeIntervalSince(now)) < 60)
        // The copy is the import's, not the picker's file.
        #expect(dated.url != pick.photos[0].url)
    }
}

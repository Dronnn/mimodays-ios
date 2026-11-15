import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

struct PersistenceTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try MimoDaysStore.makeContainer(inMemory: true))
    }

    private func makeMoment(day: Int = 2026_11_11, origin: MomentOrigin = .manual, type: MediaType = .photo) -> Moment {
        Moment(capturedAt: Date(timeIntervalSince1970: 1_794_412_920), timeZoneID: "America/Los_Angeles", localDay: day, origin: origin, mediaType: type)
    }

    @Test func schemaHoldsEveryEntityOfVersionOne() {
        #expect(SchemaV1.models.count == 15)
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(MimoDaysMigrationPlan.schemas.count == 1)
    }

    @Test func deletingMomentRemovesItsMediaVoiceAndPlace() throws {
        let context = try makeContext()
        let moment = makeMoment()
        context.insert(moment)
        moment.media.append(MomentMedia(role: .rearSource, relativePath: "originals/a.jpg", uniformType: "public.jpeg", pixelWidth: 900, pixelHeight: 1200, checksum: "abc", byteCount: 1))
        moment.voiceNotes.append(MomentVoiceNote(relativePath: "voice/a.m4a", duration: 2, recordedAt: .now, transcript: "look at her go"))
        moment.location = MomentLocation(latitude: 37.80, longitude: -122.26, precision: .city, source: .gps, placeLabel: "Oakland")
        try context.save()

        context.delete(moment)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<MomentMedia>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MomentVoiceNote>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MomentLocation>()) == 0)
    }

    @Test func collectionKeepsOrderAndSurvivesMomentDeletion() throws {
        let context = try makeContext()
        let collection = MomentCollection(title: "Lena's firsts", sortOrder: 0)
        context.insert(collection)
        let moments = (0..<3).map { _ in makeMoment() }
        moments.forEach(context.insert)
        for (position, moment) in moments.reversed().enumerated() {
            context.insert(CollectionMembership(collection: collection, moment: moment, position: position))
        }
        try context.save()
        #expect(collection.orderedMoments.map(\.id) == moments.reversed().map(\.id))

        context.delete(moments[0])
        try context.save()
        #expect(collection.orderedMoments.count == 2)
        #expect(try context.fetchCount(FetchDescriptor<MomentCollection>()) == 1)
    }

    @Test func softDeletedMomentsAreExcludedByPredicate() throws {
        let context = try makeContext()
        let kept = makeMoment()
        let deleted = makeMoment()
        deleted.deletedAt = .now
        [kept, deleted].forEach(context.insert)
        try context.save()

        let visible = try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.deletedAt == nil }))
        #expect(visible.map(\.id) == [kept.id])
    }

    @Test func storedEnumsWorkInPredicates() throws {
        let context = try makeContext()
        context.insert(makeMoment(origin: .randomPrompt, type: .video))
        context.insert(makeMoment(origin: .manual, type: .photo))
        try context.save()

        let surprise = MomentOrigin.randomPrompt.rawValue
        let videos = MediaType.video.rawValue
        let found = try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.originRaw == surprise && $0.mediaTypeRaw == videos }))
        #expect(found.count == 1)
        #expect(found.first?.origin == .randomPrompt)
    }

    @Test func movieProjectDeletesClipsButNotMoments() throws {
        let context = try makeContext()
        let moment = makeMoment()
        context.insert(moment)
        let project = MovieProject(title: "November", sourceRule: MovieSourceRule(kind: .dateRange, start: .distantPast, end: .now), aspectRatio: .portrait9x16, length: .short)
        context.insert(project)
        context.insert(MovieClip(project: project, moment: moment, position: 0))
        let track = MovieAudioTrack(kind: .soundtrack, relativePath: "audio/song.m4a")
        track.gainEnvelope = [GainPoint(time: 0, gain: 0), GainPoint(time: 1, gain: 1)]
        project.audioTracks.append(track)
        try context.save()

        context.insert(MovieTextCard(project: project, position: 1, text: "First ride"))
        try context.save()

        context.delete(project)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<MovieClip>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MovieTextCard>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MovieAudioTrack>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Moment>()) == 1)
    }

    @Test func formatsLayoutsAtmosphereAndTextCardsReopenFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let voiceID = UUID()
        do {
            let context = ModelContext(try MimoDaysStore.makeContainer(url: url))
            let moment = makeMoment(type: .video)
            #expect(moment.captureFormat == .portrait)
            moment.captureFormat = .landscape
            context.insert(moment)
            let project = MovieProject(title: "November", sourceRule: MovieSourceRule(kind: .dateRange, start: .distantPast, end: .now), aspectRatio: .landscape16x9, length: .short)
            context.insert(project)
            let clip = MovieClip(project: project, moment: moment, position: 1)
            #expect(clip.cameraLayout == nil && clip.pipFrame == nil && clip.atmosphere == nil)
            clip.cameraLayout = .swapped
            clip.pipFrame = PiPLayout(centerX: 0.3, centerY: 0.7, scale: 0.4)
            clip.atmosphere = MovieAtmosphere(lead: 3, leadsWith: .voiceComment)
            context.insert(clip)
            let card = MovieTextCard(project: project, position: 0, text: "Lena's first ride", look: .plum, duration: 5)
            card.voiceNoteID = voiceID
            context.insert(card)
            try context.save()
        }

        let context = ModelContext(try MimoDaysStore.makeContainer(url: url))
        let moment = try #require(try context.fetch(FetchDescriptor<Moment>()).first)
        #expect(moment.captureFormat == .landscape)
        let project = try #require(try context.fetch(FetchDescriptor<MovieProject>()).first)
        let clip = try #require(project.clips.first)
        #expect(clip.cameraLayout == .swapped)
        #expect(clip.pipFrame == PiPLayout(centerX: 0.3, centerY: 0.7, scale: 0.4))
        #expect(clip.atmosphere == MovieAtmosphere(lead: 3, leadsWith: .voiceComment))
        let card = try #require(project.textCards.first)
        #expect(card.text == "Lena's first ride" && card.look == .plum && card.duration == 5 && card.position == 0)
        #expect(card.voiceNoteID == voiceID && card.transition == .cut)
    }

    @Test func atmosphereLeadStaysWithinItsRange() {
        #expect(MovieAtmosphere().lead == 2)
        #expect(MovieAtmosphere(lead: 0.1).lead == 0.5)
        #expect(MovieAtmosphere(lead: 9).lead == 5)
    }

    @Test func exportsLeavePlaceAndVoiceOutByDefault() {
        let job = ExportJob(kind: .selection, sourceIDs: [UUID()], destination: .files)
        #expect(!job.options.includesLocation)
        #expect(!job.options.includesVoiceNotes)
        #expect(job.state == .queued)
        #expect(!AppPreferences().defaultExportOptions.includesLocation)
    }

    @Test func storeOnDiskReopensWithData() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("MimoDays.store")
        let id: UUID
        do {
            let context = ModelContext(try MimoDaysStore.makeContainer(url: url))
            let schedule = SurpriseSchedule(frequency: .twiceADay)
            context.insert(schedule)
            let moment = makeMoment()
            moment.pipLayout = PiPLayout(centerX: 0.8, centerY: 0.2, scale: 0.3)
            moment.tags = ["bike"]
            id = moment.id
            context.insert(moment)
            try context.save()
        }
        let context = ModelContext(try MimoDaysStore.makeContainer(url: url))
        let moment = try #require(try context.fetch(FetchDescriptor<Moment>()).first)
        #expect(moment.id == id)
        #expect(moment.pipLayout?.rotation == -5.4)
        #expect(moment.tags == ["bike"])
        #expect(try context.fetch(FetchDescriptor<SurpriseSchedule>()).first?.frequency == .twiceADay)
    }
}

struct MomentCaptureTimeTests {
    @Test func dayAndZoneComeFromCaptureTime() throws {
        let captured = CaptureTime(instant: try Date("2026-11-12T07:30:00Z", strategy: .iso8601), timeZoneID: "America/Los_Angeles")
        let moment = Moment(captured: captured, origin: .manual, mediaType: .photo, createdAt: captured.instant)
        #expect(moment.localDay == 2026_11_11)
        #expect(moment.captureTime == captured)
    }
}

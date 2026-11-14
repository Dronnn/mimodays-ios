@preconcurrency import AVFoundation
import Core
import DesignSystem
import SwiftData
import SwiftUI

/// Keeps the viewer's model while it's on screen; any screen can open it from a `MomentPager`.
struct MomentViewerScreen: View {
    let pager: MomentPager
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library {
            MomentViewerHost(model: MomentViewerModel(pager: pager, library: library))
        }
    }
}

private struct MomentViewerHost: View {
    @State var model: MomentViewerModel

    var body: some View {
        MomentViewer(model: model)
    }
}

/// M05 (photo) and M06 (video): one moment per page, swiping sideways to the others it was opened among.
/// A photo sits on the cream canvas; a video fills the screen, with cream controls.
struct MomentViewer: View {
    @Bindable var model: MomentViewerModel
    @Environment(\.camera) private var camera
    /// M07 while it is open.
    @State private var editing: EditMomentModel?

    private var isVideo: Bool { model.currentMoment?.mediaType == .video }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(model.ids, id: \.self) { id in
                    page(id)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .task { await model.load(id) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $model.current)
        .scrollIndicators(.hidden)
        .background((isVideo ? Color.black : ColorToken.canvas.color).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        // A solid bar would cover the top of each page; the canvas behind it is the same colour anyway.
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(isVideo ? .dark : nil, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let moment = model.currentMoment {
                    Self.time(moment.captured, date: false)
                        .textStyle(.editorTitle)
                        .foregroundStyle((isVideo ? ColorToken.mediaFrame : .textPrimary).color)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let moment = model.currentMoment { actions(moment) }
        }
        .fullScreenCover(item: $editing) { EditMomentView(model: $0) }
        .onChange(of: model.current) { model.stopVoice() }
        .onDisappear { model.stopVoice() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await model.reload() }
        }
    }

    @ViewBuilder
    private func page(_ id: UUID) -> some View {
        if let moment = model.moments[id] {
            if moment.mediaType == .video {
                VideoPage(model: model, moment: moment, isCurrent: model.current == id)
            } else {
                photoPage(moment)
            }
        } else {
            Color.clear
        }
    }

    // MARK: Photo (M05)

    private func photoPage(_ moment: ViewerMoment) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color(hex: 0x9C8573)
                    .overlay {
                        if let image = model.image(moment.mainPath) { Image(uiImage: image).resizable().scaledToFill() }
                    }
                    .aspectRatio(386 / 440, contentMode: .fit)
                    .clipShape(ViewerPhotoBlob())
                    .overlay(alignment: .topTrailing) {
                        if let selfie = moment.selfiePath {
                            SelfieWindow(media: model.image(selfie).map { .image(Image(uiImage: $0)) } ?? .placeholder)
                                .frame(width: 89, height: 110)
                                .padding(.top, 10)
                                .padding(.trailing, 24)
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityElement()
                    .accessibilityLabel(Text(moment.selfiePath == nil ? "Photo" : "Photo with selfie", bundle: .module))
                    .accessibilityAddTraits(.isImage)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                meta(moment)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                MomentWords(moment: moment, onPhoto: false)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                if let voice = moment.voice {
                    VoicePill(model: model, id: moment.id, voice: voice, onPhoto: false)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }
                if !moment.collections.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(moment.collections) { collection in
                                NavigationLink(value: MemoriesRoute.collection(collection.id)) {
                                    SearchChip(icon: .glyphCollection, title: Text(collection.title), isOn: false, id: "") {}
                                        .allowsHitTesting(false)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("viewer.collection")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.top, 10)
                }
            }
            .padding(.bottom, 20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    /// The place on the left, where it came from and when on the right.
    private func meta(_ moment: ViewerMoment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let place = moment.place {
                HStack(spacing: 4) {
                    Icon.glyphPin.image
                        .resizable()
                        .frame(width: 20, height: 20)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    Text(place)
                        .textStyle(.viewerPlace)
                }
                .foregroundStyle(ColorToken.textPrimary.color)
            }
            Spacer(minLength: 8)
            OriginLabel(origin: moment.origin, time: Self.time(moment.captured, date: true), order: .originFirst)
                .textStyle(.viewerMeta)
                .foregroundStyle(ColorToken.textSecondary.color)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Actions

    /// Share, favourite and edit; deleting arrives with its own step.
    private func actions(_ moment: ViewerMoment) -> some View {
        let tint = (isVideo ? ColorToken.mediaFrame : .textPrimary).color
        return HStack {
            if moment.mediaType == .photo, let url = model.url(moment.composedPath) {
                ShareLink(item: url) {
                    Icon.glyphShare.image.resizable().frame(width: 24, height: 24).foregroundStyle(tint)
                        .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                }
                .accessibilityLabel(Text("Share", bundle: .module))
                .accessibilityIdentifier("viewer.share")
                .frame(maxWidth: .infinity)
            }
            Button { model.toggleFavorite(moment.id) } label: {
                (moment.isFavorite ? Icon.glyphHeartFilled : .glyphHeart).image
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(moment.isFavorite ? ColorToken.actionCoral.color : tint)
                    .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: moment.isFavorite)
            .accessibilityLabel(Text("Favorite", bundle: .module))
            .accessibilityAddTraits(moment.isFavorite ? .isSelected : [])
            .accessibilityIdentifier("viewer.favorite")
            .frame(maxWidth: .infinity)
            Button { edit(moment.id) } label: {
                Icon.glyphNote.image
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(tint)
                    .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit", bundle: .module))
            .accessibilityIdentifier("viewer.edit")
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background {
            (isVideo ? Color(hex: 0x1F1418).opacity(0.55) : ColorToken.canvas.color)
                .overlay(alignment: .top) {
                    Rectangle().fill((isVideo ? ColorToken.mediaFrame : .textPrimary).color.opacity(0.14)).frame(height: 0.6)
                }
                .ignoresSafeArea()
        }
    }

    private func edit(_ id: UUID) {
        model.stopVoice()
        let services = camera ?? .simulated
        editing = EditMomentModel(id: id, library: model.library, voice: services.voice, places: services.places)
    }

    // MARK: Pieces

    /// "6:42 PM", or "Wed, Nov 11, 2026 · 6:42 PM", in the moment's own time zone.
    static func time(_ captured: CaptureTime, date: Bool) -> Text {
        var clock = Date.FormatStyle(date: .omitted, time: .shortened)
        clock.timeZone = captured.timeZone
        guard date else { return Text(captured.instant, format: clock) }
        var day = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day().year()
        day.timeZone = captured.timeZone
        return Text("Day and time: \(Text(captured.instant, format: day)) · \(Text(captured.instant, format: clock))", bundle: .module)
    }
}

/// A moment's caption, then its longer note; cream on a video.
struct MomentWords: View {
    let moment: ViewerMoment
    let onPhoto: Bool

    var body: some View {
        let color = (onPhoto ? ColorToken.mediaFrame : .textPrimary).color
        VStack(alignment: .leading, spacing: 6) {
            if let title = moment.title {
                Text(title)
                    .textStyle(.dayCaption)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = moment.note {
                Text(note)
                    .textStyle(.body)
                    .foregroundStyle(onPhoto ? color : ColorToken.textBody.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// `Viewer / Voice pill`: play or stop, its length and its waveform. Cream on a video.
struct VoicePill: View {
    let model: MomentViewerModel
    let id: UUID
    let voice: ViewerMoment.Voice
    let onPhoto: Bool

    var body: some View {
        let isPlaying = model.playingVoice == id
        let ink = (onPhoto ? ColorToken.mediaFrame : .textPrimary).color
        Button { model.toggleVoice(id) } label: {
            HStack(spacing: 12) {
                (isPlaying ? Icon.glyphPause : .glyphPlay).image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(onPhoto ? ink : ColorToken.textOnCoral.color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(onPhoto ? Color.clear : ColorToken.actionCoral.color))
                Text("Voice note · \(Text(Duration.seconds(voice.duration.rounded()), format: .time(pattern: .minuteSecond)))", bundle: .module)
                    .textStyle(.reviewChip)
                    .foregroundStyle(ink)
                if !onPhoto {
                    WaveformBars(
                        levels: model.voiceLevels[id] ?? [], count: MomentViewerModel.voiceBars, filled: 0,
                        minHeight: 6, maxHeight: 22, rest: ColorToken.textPrimary.color.opacity(0.55)
                    )
                    .frame(height: 24)
                    .accessibilityHidden(true)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(minHeight: onPhoto ? 40 : 52)
            .frame(maxWidth: onPhoto ? nil : .infinity, alignment: .leading)
            .background {
                if onPhoto {
                    Capsule().fill(ColorToken.mediaFrame.color.opacity(0.18))
                } else {
                    FieldBlob().fill(ColorToken.surfaceChip.color)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Voice note · \(Text(Duration.seconds(voice.duration.rounded()), format: .time(pattern: .minuteSecond)))", bundle: .module))
        .accessibilityHint(Text(isPlaying ? "Stops it" : "Plays it", bundle: .module))
        .accessibilityIdentifier("viewer.voice")
    }
}

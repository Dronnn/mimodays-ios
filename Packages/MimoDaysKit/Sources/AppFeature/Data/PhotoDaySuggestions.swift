@preconcurrency import AVFoundation
import Core
import DesignSystem
import Foundation
import OSLog
import Photos
import SwiftUI
import UIKit

/// P8.5: what Photos holds for one day, read only once the person asks (EE02), through the read access PhotoKit gives.
protocol PhotoDayLibrary: Sendable {
    func access() -> PhotoDayAccess
    func requestAccess() async -> PhotoDayAccess
    /// The day's photos and videos (yyyymmdd in the device's time zone), newest first.
    func assets(on day: Int) async throws -> [PhotoDayAsset]
    func thumbnail(_ id: String) async -> UIImage?
    /// The original file, a Live Photo with its motion, copied to tmp for Import.
    func file(_ id: String) async throws -> PickedFile?
}

enum PhotoDayAccess: Equatable, Sendable {
    case notDetermined
    case full
    /// Only the photos the person chose: "Choose more photos".
    case limited
    case denied
}

struct PhotoDayAsset: Identifiable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let isVideo: Bool
    let isLivePhoto: Bool
    let duration: Double
}

/// One chosen asset handed to Import like a picker item.
struct PhotoDayItem: PhotoPickerItemLoading {
    let id: String
    let library: any PhotoDayLibrary

    func loadFile() async throws -> PickedFile? { try await library.file(id) }
}

// MARK: - Model

@MainActor
@Observable
final class PhotoDayModel: Identifiable {
    enum Phase: Equatable {
        /// EE03: our explainer before the first iOS prompt.
        case explainer
        case loading
        case ready
        /// "No photos or videos from this day".
        case empty
        /// EE04.
        case denied
        /// "Couldn't load this day".
        case failed
    }

    let day: Int
    private(set) var phase = Phase.loading
    private(set) var assets: [PhotoDayAsset] = []
    private(set) var thumbnails: [String: UIImage] = [:]
    private(set) var isLimited = false
    var picked: Set<String> = []
    let library: any PhotoDayLibrary
    private let logger = Logger(subsystem: "MimoDays", category: "PhotoDay")

    nonisolated var id: Int { day }

    init(day: Int, library: any PhotoDayLibrary) {
        self.day = day
        self.library = library
    }

    private var started = false

    /// Where the sheet starts: the explainer before iOS has asked, else the day's photos. Once.
    func start() async {
        guard !started else { return }
        started = true
        switch library.access() {
        case .notDetermined: phase = .explainer
        case .denied: phase = .denied
        case .full, .limited: await load()
        }
    }

    /// EE03's Continue: iOS asks, then the day loads or EE04 shows.
    func requestAccess() async {
        phase = .loading
        if await library.requestAccess() == .denied { phase = .denied } else { await load() }
    }

    func load() async {
        isLimited = library.access() == .limited
        // A reload (Choose more photos, Try again) keeps the grid it has.
        if assets.isEmpty { phase = .loading }
        do {
            assets = try await library.assets(on: day)
        } catch {
            logger.error("Reading the day in Photos failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed
            return
        }
        picked.formIntersection(assets.map(\.id))
        phase = assets.isEmpty ? .empty : .ready
        for asset in assets where thumbnails[asset.id] == nil {
            thumbnails[asset.id] = await library.thumbnail(asset.id)
        }
    }

    func toggle(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    /// Review: what Import loads, in the order shown.
    var items: [PhotoDayItem] {
        assets.filter { picked.contains($0.id) }.map { PhotoDayItem(id: $0.id, library: library) }
    }
}

// MARK: - PhotoKit

/// The day's assets through PhotoKit's read access; nothing is copied until Import.
struct SystemPhotoDayLibrary: PhotoDayLibrary {
    func access() -> PhotoDayAccess { Self.access(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }

    func requestAccess() async -> PhotoDayAccess {
        Self.access(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    private static func access(_ status: PHAuthorizationStatus) -> PhotoDayAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .full
        case .limited: .limited
        default: .denied
        }
    }

    func assets(on day: Int) async throws -> [PhotoDayAsset] {
        let calendar = Calendar.current
        guard let start = calendar.date(from: DateComponents(year: day / 10_000, month: day / 100 % 100, day: day % 100)),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@ AND (mediaType == %d OR mediaType == %d)",
            start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PhotoDayAsset] = []
        result.enumerateObjects { asset, _, _ in
            guard let created = asset.creationDate else { return }
            assets.append(PhotoDayAsset(
                id: asset.localIdentifier, createdAt: created, isVideo: asset.mediaType == .video,
                isLivePhoto: asset.mediaSubtypes.contains(.photoLive), duration: asset.duration
            ))
        }
        // Newest first, the id deciding a tie so the grid doesn't reorder.
        return assets.sorted { ($0.createdAt, $1.id) > ($1.createdAt, $0.id) }
    }

    func thumbnail(_ id: String) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func file(_ id: String) async throws -> PickedFile? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        func pick(_ types: [PHAssetResourceType]) -> PHAssetResource? {
            types.lazy.compactMap { type in resources.first { $0.type == type } }.first
        }
        if asset.mediaType == .video {
            guard let video = pick([.fullSizeVideo, .video]) else { return nil }
            return PickedFile(url: try await Self.write(video), isVideo: true)
        }
        guard let still = pick([.fullSizePhoto, .photo]) else { return nil }
        let url = try await Self.write(still)
        guard asset.mediaSubtypes.contains(.photoLive) else { return PickedFile(url: url, isVideo: false) }
        // Its motion, or the still alone marked so Import asks first (P8.6).
        let motion = try? await pick([.fullSizePairedVideo, .pairedVideo]).asyncMap(Self.write)
        return PickedFile(url: url, isVideo: false, motionURL: motion, isLivePhoto: true)
    }

    private static func write(_ resource: PHAssetResource) async throws -> URL {
        let target = try PickedFile.target(extension: (resource.originalFilename as NSString).pathExtension)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: options)
        return target
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}

// MARK: - Sheet

/// EE02-EE04: "From this day", the day's photos and videos to pick, Review {N}; Import (E05) after it.
struct PhotoDaySheet: View {
    @Bindable var model: PhotoDayModel
    let close: () -> Void
    let review: () -> Void
    /// EE04, empty: the system picker, for any date.
    let browse: () -> Void
    @Environment(\.openURL) private var openURL

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            TitleBar {
                Button(action: close) {
                    Text("Cancel", bundle: .module).textStyle(.editorCancel).foregroundStyle(ColorToken.textPrimary.color)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("photoSuggestions.cancel")
            } title: {
                Text("From this day", bundle: .module)
                    .textStyle(.editorTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(minHeight: Size.minimumTapTarget)
            .padding(.horizontal, 16)
            content
        }
        .background(ColorToken.surfaceSheet.color.ignoresSafeArea())
        .task { await model.start() }
    }

    private var dayTitle: some View {
        Text(MemoriesView.dayDate(model.day), format: Date.FormatStyle(timeZone: .gmt).weekday(.wide).month(.wide).day())
            .textStyle(.sheetTitle)
            .foregroundStyle(ColorToken.textPrimary.color)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .explainer:
            explainer(
                title: Text("Find moments from this day in Photos", bundle: .module),
                message: Text("MimoDays looks only at photos and videos taken on this date, on this iPhone. Nothing is copied until you pick it and tap Import.", bundle: .module)
            ) {
                Button { Task { await model.requestAccess() } } label: { Text("Continue", bundle: .module) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("photoSuggestions.continue")
            }
        case .loading:
            dayTitle
            Spacer()
            HStack(spacing: 10) {
                ProgressView()
                Text("Looking in Photos…", bundle: .module)
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textSecondary.color)
            }
            Spacer()
        case .ready:
            grid
        case .empty:
            dayTitle
            notice(Text("No photos or videos from this day", bundle: .module)) {
                if model.isLimited { chooseMore }
                browseButton
            }
        case .denied:
            dayTitle
            notice(Text("Allow Photos access in iOS Settings to find moments by date.", bundle: .module)) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Text("Open iOS Settings", bundle: .module) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("photoSuggestions.settings")
                browseButton
                Text("Browse Photos opens the system picker: no access needed.", bundle: .module)
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .multilineTextAlignment(.center)
            }
        case .failed:
            dayTitle
            notice(Text("Couldn't load this day", bundle: .module)) {
                Button { Task { await model.load() } } label: { Text("Try again", bundle: .module) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("photoSuggestions.retry")
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    dayTitle
                    Text("\(Text("\(model.assets.count) photos and videos", bundle: .module)) in Photos. Pick the ones to keep.", bundle: .module)
                        .textStyle(.rowCaption)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(model.assets) { tile($0) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    if model.isLimited {
                        chooseMore.padding(.top, 16).frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 16)
            }
            Button(action: review) { Text("Review \(model.picked.count)", bundle: .module) }
                .buttonStyle(WizardButtonStyle())
                .disabled(model.picked.isEmpty)
                .accessibilityIdentifier("photoSuggestions.review")
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }

    private func tile(_ asset: PhotoDayAsset) -> some View {
        let isOn = model.picked.contains(asset.id)
        return Button { model.toggle(asset.id) } label: {
            Color(hex: 0xC9B8AA)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = model.thumbnails[asset.id] { Image(uiImage: image).resizable().scaledToFill() }
                }
                .clipShape(StripTile.shape(asset.createdAt))
                .overlay(alignment: .topLeading) {
                    if asset.isLivePhoto { LiveBadge().scaleEffect(0.85, anchor: .topLeading).padding(6) }
                }
                .overlay(alignment: .bottomLeading) {
                    if asset.isVideo { VideoBadge(duration: asset.duration).padding(6) }
                }
                .overlay { SelectionMark(isOn: isOn, shape: StripTile.shape(asset.createdAt)) }
                .contentShape(Rectangle())
                // Badges and the mark keep their corners, like every grid of pictures here.
                .environment(\.layoutDirection, .leftToRight)
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: [
            String(appLocalized: asset.isVideo ? "Video" : asset.isLivePhoto ? "Live Photo" : "Photo", bundle: .module),
            asset.createdAt.formatted(date: .omitted, time: .shortened),
        ].joined(separator: ", ")))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("photoSuggestions.tile")
    }

    private var chooseMore: some View {
        Button {
            Self.presentLimitedPicker { Task { await model.load() } }
        } label: { Text("Choose more photos", bundle: .module) }
            .buttonStyle(.text)
            .accessibilityIdentifier("photoSuggestions.chooseMore")
    }

    private var browseButton: some View {
        Button(action: browse) { Text("Browse Photos", bundle: .module) }
            .buttonStyle(.text)
            .accessibilityIdentifier("photoSuggestions.browse")
    }

    private func explainer(title: Text, message: Text, @ViewBuilder action: () -> some View) -> some View {
        fitting(VStack(spacing: 0) {
            Spacer(minLength: 20)
            ExplainerArt(glyph: .explainerPhotos)
            title
                .textStyle(.emptyTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 24)
            message
                .textStyle(.emptyBody)
                .foregroundStyle(ColorToken.textBody.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Spacer(minLength: 20)
            action()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8))
    }

    private func notice(_ text: Text, @ViewBuilder actions: () -> some View) -> some View {
        fitting(VStack(spacing: 0) {
            Spacer(minLength: 20)
            ExplainerArt(glyph: .explainerPhotos)
            text
                .textStyle(.emptyBody)
                .foregroundStyle(ColorToken.textPrimary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
            Spacer(minLength: 20)
            VStack(spacing: 10, content: actions)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8))
    }

    /// Spread over the sheet when it fits, scrolling at the largest text sizes.
    private func fitting(_ content: some View) -> some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }

    /// iOS's own picker for adding photos to the ones MimoDays may see.
    private static func presentLimitedPicker(done: @escaping @MainActor @Sendable () -> Void) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { _ in
            Task { @MainActor in done() }
        }
    }
}

// MARK: - Flow

extension View {
    /// P8.5: Find moments in Photos for an empty day; then E05 Import for what was picked.
    func photoDaySuggestions(day: Binding<Int?>) -> some View {
        modifier(PhotoDayFlow(day: day))
    }
}

private struct PhotoDayFlow: ViewModifier {
    @Binding var day: Int?
    @State private var suggestions: PhotoDayModel?
    @State private var importing: PhotoImportModel?
    @State private var browses = false
    @Environment(\.mediaLibrary) private var library
    @Environment(\.momentSaver) private var saver
    @Environment(\.camera) private var services
    @Environment(\.photoDayLibrary) private var photos

    func body(content: Content) -> some View {
        content
            .onChange(of: day) { _, day in
                guard let day else { return }
                suggestions = PhotoDayModel(day: day, library: photos)
            }
            .sheet(item: $suggestions, onDismiss: { day = nil }) { model in
                PhotoDaySheet(model: model) {
                    suggestions = nil
                } review: {
                    guard let library, let saver, let lookup = services?.places.lookup else { return }
                    let items = model.items
                    suggestions = nil
                    let importModel = PhotoImportModel(library: library, saver: saver, lookup: lookup)
                    importModel.start(items)
                    // After the sheet has gone.
                    Task { @MainActor in importing = importModel }
                } browse: {
                    suggestions = nil
                    Task { @MainActor in browses = true }
                }
                .presentationDetents([.large])
            }
            .fullScreenCover(item: $importing) { model in
                PhotoImportView(model: model) {
                    model.discard()
                    importing = nil
                } imported: {
                    model.discard()
                    importing = nil
                }
            }
            .photoImport(isPresented: $browses)
    }
}

private struct PhotoDayLibraryKey: EnvironmentKey {
    static let defaultValue: any PhotoDayLibrary = SystemPhotoDayLibrary()
}

extension EnvironmentValues {
    /// PhotoKit, or a stand-in in tests and previews.
    var photoDayLibrary: any PhotoDayLibrary {
        get { self[PhotoDayLibraryKey.self] }
        set { self[PhotoDayLibraryKey.self] = newValue }
    }
}

/// EE01: "Find moments in Photos", on Today and under an empty calendar day.
struct PhotosSuggestionsLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.glyphPhotos.image
                    .resizable()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text("Find moments in Photos", bundle: .module)
                    .textStyle(.rowCaption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(ColorToken.textLink.color)
            .frame(minHeight: Size.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

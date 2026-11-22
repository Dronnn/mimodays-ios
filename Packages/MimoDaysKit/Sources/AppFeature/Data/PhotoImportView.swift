import Core
import DesignSystem
import Photos
import PhotosUI
import SwiftUI

/// E05: what was picked, where it goes, and "Import N" for the ones not already here.
struct PhotoImportView: View {
    @Bindable var model: PhotoImportModel
    let close: () -> Void
    let imported: () -> Void
    @State private var failed = false
    /// "Keep motion" didn't take.
    @State private var motionNotKept = false
    /// False once the screen is gone (a notification took over): a batch that ends then doesn't move the app.
    @State private var isShown = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            TitleBar {
                Button(action: close) {
                    Text("Cancel", bundle: .module).textStyle(.editorCancel).foregroundStyle(ColorToken.textPrimary.color)
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                .accessibilityIdentifier("import.cancel")
            } title: {
                Text("Import", bundle: .module)
                    .textStyle(.editorTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(minHeight: Size.minimumTapTarget)
            .padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tiles
                    if case let .loading(progress) = model.phase {
                        ProgressView(value: progress)
                            .tint(ColorToken.actionCoral.color)
                            .padding(.top, 24)
                    } else {
                        summary
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            Button {
                Task {
                    let done = await model.importAll()
                    guard isShown else { return model.discard() }
                    if done { imported() } else { failed = true }
                }
            } label: {
                if case let .importing(progress) = model.phase {
                    Text("Importing \(progress.formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.shared.locale)))", bundle: .module)
                } else {
                    Text("Import \(model.new.count)", bundle: .module)
                }
            }
            .buttonStyle(.primary)
            .disabled(model.phase != .ready || model.new.isEmpty)
            .accessibilityIdentifier("import.start")
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .interactiveDismissDisabled(isImporting)
        .onDisappear { isShown = false }
        .alert(Text("Some files couldn't be imported", bundle: .module), isPresented: $failed) {
            Button(action: imported) { Text("OK", bundle: .module) }
        } message: {
            Text("The others are in Memories. Try the rest again from Photos.", bundle: .module)
        }
    }

    private var isImporting: Bool {
        if case .importing = model.phase { true } else { false }
    }

    /// Up to eight; the eighth says how many more there are.
    private var tiles: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(model.picked.prefix(8)) { item in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let image = model.thumbnails[item.id] {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Color(hex: 0xC9B8AA)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if item.isVideo, let duration = item.duration { VideoBadge(duration: duration).padding(6) }
                    }
                    .overlay(alignment: .topLeading) {
                        // P8.6: a Live Photo with its motion.
                        if item.motionURL != nil { LiveBadge().scaleEffect(0.85, anchor: .topLeading).padding(5) }
                    }
                    .overlay {
                        // Its motion didn't come: waiting for Try again, Import as still or Skip.
                        if model.motionFailed.contains(item.id) {
                            StripTile.shape(item.id)
                                .stroke(ColorToken.actionCoral.color, lineWidth: 5)
                                .clipShape(StripTile.shape(item.id))
                                .overlay(alignment: .topTrailing) {
                                    Icon.glyphWarning.image
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                        .foregroundStyle(ColorToken.actionCoral.color)
                                        .padding(6)
                                }
                        }
                    }
                    .overlay {
                        if item.id == model.picked.prefix(8).last?.id, model.count > 8 {
                            ZStack {
                                ColorToken.mediaScrim.color
                                Text(verbatim: "+\(model.count - 7)").textStyle(.sheetTitle).foregroundStyle(.white)
                            }
                        }
                    }
                    // Hand-cut like every tile.
                    .clipShape(StripTile.shape(item.id))
                    .accessibilityHidden(true)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
                .textStyle(.sheetTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 2)
                .padding(.top, 12)
            Text("Each one goes to the day it was taken and is marked \"Imported\". They have no selfie window. The originals stay in Photos.", bundle: .module)
                .textStyle(TextStyle(.body, size: 14.5, weight: 500, lineHeight: 1.2, relativeTo: .subheadline))
                .foregroundStyle(ColorToken.textBody.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.top, 7)
            DataCard {
                DataToggleRow(title: Text("Keep the place from Photos", bundle: .module), detail: Text("city level", bundle: .module), isOn: $model.keepsPlace)
                    .disabled(isImporting)
                    .accessibilityIdentifier("import.place")
                if !model.skipped.isEmpty {
                    DataSeparator()
                    HStack {
                        Text("Already in MimoDays", bundle: .module).textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
                        Spacer(minLength: 8)
                        Text("\(model.skipped.count) skipped", bundle: .module).textStyle(.rowValue).foregroundStyle(ColorToken.textTertiary.color)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: 52)
                    .accessibilityElement(children: .combine)
                }
                if !model.motionToAttach.isEmpty {
                    DataSeparator()
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Already here without motion", bundle: .module).textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
                            Text("Its motion can join the moment that's here.", bundle: .module)
                                .textStyle(.rowCaption)
                                .foregroundStyle(ColorToken.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button {
                            Task { if await !model.attachAllMotion() { motionNotKept = true } }
                        } label: { Text("Keep motion", bundle: .module) }
                            .buttonStyle(ChipButtonStyle())
                            .disabled(isImporting)
                            .accessibilityIdentifier("import.keepMotion")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 52)
                }
            }
            .padding(.top, 20)
            if !model.motionFailed.isEmpty {
                motionFailedCard.padding(.top, 14)
                Text("Still loading or failed items aren't counted until resolved.", bundle: .module)
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
        }
        .alert(Text("Motion couldn't be kept", bundle: .module), isPresented: $motionNotKept) {
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: {
            Text("The moment that's here stays as it was.", bundle: .module)
        }
    }

    /// P8.6 EE05: Live Photos whose motion didn't come.
    private var motionFailedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Icon.glyphWarning.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.actionCoral.color)
                    .accessibilityHidden(true)
                Text("Motion couldn't be loaded", bundle: .module)
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
            }
            Text("The still picture can come in now, without its motion.", bundle: .module)
                .textStyle(.rowCaption)
                .foregroundStyle(ColorToken.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            ChipFlow(spacing: 8, lineSpacing: 8) {
                Button { Task { await model.retryMotion() } } label: {
                    if model.isRetrying { Text("Loading motion…", bundle: .module) } else { Text("Try again", bundle: .module) }
                }
                .accessibilityIdentifier("import.liveRetry")
                Button { model.motionFailed.forEach(model.importAsStill) } label: { Text("Import as still", bundle: .module) }
                    .accessibilityIdentifier("import.liveStill")
                Button { model.motionFailed.forEach(model.skip) } label: { Text("Skip", bundle: .module) }
                    .accessibilityIdentifier("import.liveSkip")
            }
            .buttonStyle(ChipButtonStyle())
            .disabled(model.isRetrying || isImporting)
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InfoCardBlob().fill(ColorToken.surfaceCard.color))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.livePhoto")
    }

    /// "8 photos and videos", "3 photos", "1 video".
    private var title: Text {
        switch (model.count - model.videos, model.videos) {
        case let (photos, 0): Text("\(photos) photos", bundle: .module)
        case let (0, videos): Text("\(videos) videos", bundle: .module)
        default: Text("\(model.count) photos and videos", bundle: .module)
        }
    }
}

extension PhotosPickerItem: PhotoPickerItemLoading {
    /// A Live Photo comes as its still and motion (P8.6): the picker's bundle, else its resources; if neither loads,
    /// the still alone, marked so E05 asks before importing it without motion.
    func loadFile() async throws -> PickedFile? {
        let isLive = supportedContentTypes.contains { $0.conforms(to: .livePhotoBundle) || $0.conforms(to: .livePhoto) }
        guard isLive else { return try await loadTransferable(type: PickedFile.self) }
        if let bundle = try? await loadTransferable(type: LivePhotoBundleFile.self) { return bundle.file }
        if let livePhoto = try? await loadTransferable(type: PHLivePhoto.self), let file = try? await LivePhotoFiles.write(livePhoto) { return file }
        var still = try await loadTransferable(type: PickedFile.self)
        still?.isLivePhoto = true
        return still
    }
}

extension View {
    /// Photos' own picker (no access asked for), then E05; Memories once the moments are in.
    func photoImport(isPresented: Binding<Bool>) -> some View {
        modifier(PhotoImportFlow(isPresented: isPresented))
    }
}

private struct PhotoImportFlow: ViewModifier {
    @Binding var isPresented: Bool
    @State private var items: [PhotosPickerItem] = []
    @State private var model: PhotoImportModel?
    @Environment(\.mediaLibrary) private var library
    @Environment(\.momentSaver) private var saver
    @Environment(\.camera) private var services
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented, selection: $items, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current,
                photoLibrary: .shared()
            )
            .onChange(of: items) { _, picked in
                guard !picked.isEmpty, let library, let saver, let lookup = services?.places.lookup else { return }
                let model = PhotoImportModel(library: library, saver: saver, lookup: lookup)
                self.model = model
                items = []
                model.start(picked)
            }
            .fullScreenCover(item: $model) { model in
                PhotoImportView(model: model) {
                    model.discard()
                    self.model = nil
                } imported: {
                    model.discard()
                    self.model = nil
                    router.isSettingsPresented = false
                    router.selectedTab = .memories
                }
            }
    }
}

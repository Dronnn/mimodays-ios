import Core
import DesignSystem
import PhotosUI
import SwiftUI

/// E05: what was picked, where it goes, and "Import N" for the ones not already here.
struct PhotoImportView: View {
    @Bindable var model: PhotoImportModel
    let close: () -> Void
    let imported: () -> Void
    @State private var failed = false

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
                    if await model.importAll() { imported() } else { failed = true }
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
                    .overlay {
                        if item.id == model.picked.prefix(8).last?.id, model.count > 8 {
                            ZStack {
                                ColorToken.mediaScrim.color
                                Text(verbatim: "+\(model.count - 7)").textStyle(.sheetTitle).foregroundStyle(.white)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            }
            .padding(.top, 20)
        }
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
    func loadFile() async throws -> PickedFile? {
        try await loadTransferable(type: PickedFile.self)
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

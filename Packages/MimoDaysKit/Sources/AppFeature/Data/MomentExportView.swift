import Core
import DesignSystem
import Foundation
import Observation
import Photos
import SwiftUI

/// E01 and E02's choices, and the files they make in a folder of their own under tmp.
@MainActor
@Observable
final class MomentExportModel: Identifiable {
    enum Failure: Equatable {
        case space(needed: Int64)
        case other
    }

    let ids: [UUID]
    let contents: MomentExporter.Contents
    /// Free space on this iPhone, when it can be read.
    let available: Int64?
    var options = MomentExporter.Options()
    /// E02: one `.zip` with the list instead of separate files.
    var archive = false
    /// How far the files are, while they're being made.
    private(set) var progress: Double?
    var failure: Failure?

    private let exporter: MomentExporter
    private var folder: URL?

    /// `exactPlace`: S06's "Exact place in exported files".
    init(ids: [UUID], library: MediaLibrary, exactPlace: Bool = false, freeSpace: () -> Int64? = BackupModel.deviceFreeSpace) {
        self.ids = ids
        exporter = MomentExporter(library: library)
        contents = exporter.contents(ids)
        available = freeSpace()
        options.exactPlace = exactPlace
    }

    /// E01's choice: the picture as seen, or the camera's own files.
    var separateOriginals: Bool {
        get { !options.asSeen }
        set {
            options.asSeen = !newValue
            options.originals = newValue
        }
    }

    var estimatedBytes: Int64 { exporter.estimatedBytes(ids, options: options) }

    /// Writes the chosen files (zipped, with `archive`). Nil when it couldn't, with `failure` set.
    func files() async -> [URL]? {
        guard progress == nil else { return nil }
        // An archive holds the files twice until it's made.
        let needed = Int64(Double(estimatedBytes) * (archive ? 2.1 : 1.05))
        if let available, available < needed {
            failure = .space(needed: needed - available)
            return nil
        }
        removeFiles()
        let root = FileManager.default.temporaryDirectory.appending(path: "Export-\(UUID().uuidString)", directoryHint: .isDirectory)
        folder = root
        let name = String(appLocalized: "MimoDays \(ids.count) moments", bundle: .module, comment: "The exported archive's file name")
        let target = root.appending(path: name, directoryHint: .isDirectory)
        let items = exporter.items(ids, options: options)
        let archive = archive
        progress = 0
        defer { progress = nil }
        let report: @Sendable (Double) -> Void = { [weak self] value in Task { @MainActor in self?.report(value) } }
        do {
            return try await Task.detached(priority: .userInitiated) {
                let files = try await MomentExporter.write(items, into: target, list: archive, progress: report)
                return archive ? [try MomentExporter.zip(target, as: "\(name).zip")] : files
            }.value
        } catch {
            failure = .other
            return nil
        }
    }

    /// Only the pictures go to Photos.
    static func pictures(_ files: [URL]) -> [URL] {
        files.filter { !["m4a", "txt", "csv", "zip"].contains($0.pathExtension.lowercased()) }
    }

    /// The last export's folder, once it's been handed on.
    func removeFiles() {
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
    }

    private func report(_ value: Double) {
        if progress != nil { progress = value }
    }
}

// MARK: - E01

/// E01: one moment from the viewer's Share - as seen or as the camera's own files, with its voice note, note and
/// place only when it has them; place off unless turned on.
struct MomentExportSheet: View {
    @State var model: MomentExportModel
    @State private var sharing: [URL]?
    @State private var saved = false
    @State private var photosProblem: PhotosSaveProblem?
    @State private var asker = PermissionAsker()
    @Environment(\.permissions) private var permissions
    @State private var height: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export moment", bundle: .module)
                .textStyle(.sheetTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
                .padding(.bottom, 13)
            SegmentedControl(selection: $model.separateOriginals, options: [false, true]) { originals in
                originals ? Text("Separate originals", bundle: .module) : Text("As you saw it", bundle: .module)
            }
            .accessibilityIdentifier("exportMoment.kind")
            DataNote(text: kindNote)
                .padding(.horizontal, 6)
                .padding(.top, 7)
            if model.contents.voice || model.contents.text || model.contents.place {
                DataCard {
                    let rows = rows
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 { DataSeparator() }
                        rows[index]
                    }
                }
                .padding(.top, 8)
            }
            HStack(spacing: 16) {
                Button { Task { await saveToPhotos() } } label: {
                    Label {
                        saved ? Text("Saved to Photos", bundle: .module) : Text("Save to Photos", bundle: .module)
                    } icon: {
                        (saved ? Icon.glyphCheck : .glyphDownload).image.resizable().frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(saved || model.progress != nil)
                .accessibilityIdentifier("exportMoment.photos")
                Button { Task { sharing = await model.files() } } label: {
                    HStack(spacing: 8) {
                        if model.progress != nil {
                            ProgressView().tint(ColorToken.textOnCoral.color)
                        } else {
                            Icon.glyphShare.image.resizable().frame(width: 20, height: 20)
                        }
                        Text("Share", bundle: .module)
                    }
                }
                .buttonStyle(.primary)
                .disabled(model.progress != nil)
                .accessibilityIdentifier("exportMoment.share")
            }
            .padding(.top, 30)
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
        .padding(.bottom, 26)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.canvas.color)
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil; model.removeFiles() } })) {
            ShareSheet(items: sharing ?? [])
        }
        .exportFailureAlert(model)
        .permissionExplainers(asker)
        .photosSaveAlert($photosProblem)
    }

    private var kindNote: Text {
        if model.separateOriginals {
            return Text("The camera's own files, front and back separately.", bundle: .module)
        }
        return model.contents.isVideo
            ? Text("One video with the selfie window, exactly as in MimoDays.", bundle: .module)
            : Text("One photo with the selfie window, exactly as in MimoDays.", bundle: .module)
    }

    private var rows: [AnyView] {
        var rows: [AnyView] = []
        if model.contents.voice {
            rows.append(AnyView(
                DataToggleRow(title: Text("Voice note", bundle: .module), detail: Text("as an audio file", bundle: .module), isOn: $model.options.voiceNotes)
                    .accessibilityIdentifier("exportMoment.voice")
            ))
        }
        if model.contents.text {
            rows.append(AnyView(
                DataToggleRow(title: Text("Note", bundle: .module), detail: Text("as a text file", bundle: .module), isOn: $model.options.notes)
                    .accessibilityIdentifier("exportMoment.note")
            ))
        }
        if model.contents.place {
            rows.append(AnyView(
                DataToggleRow(
                    title: Text("Exact place", bundle: .module), detail: Text("hidden unless you turn it on", bundle: .module), isOn: $model.options.exactPlace
                )
                .accessibilityIdentifier("exportMoment.place")
            ))
        }
        return rows
    }

    private func saveToPhotos() async {
        _ = await asker.request(.photoLibrary, using: permissions)
        guard let files = await model.files() else { return }
        defer { model.removeFiles() }
        do {
            try await MovieFiles.saveToPhotos(MomentExportModel.pictures(files))
            saved = true
        } catch MovieFiles.Failure.notAllowed {
            photosProblem = .notAllowed
        } catch {
            photosProblem = .other
        }
    }
}

// MARK: - E02

/// E02: the selected moments as separate files or one archive with a list; voice notes and notes on, the
/// camera's own files and exact places off.
struct MomentsExportView: View {
    @State var model: MomentExportModel
    let close: () -> Void
    @State private var sharing: [URL]?

    var body: some View {
        VStack(spacing: 0) {
            TitleBar {
                Button(action: close) {
                    Text("Cancel", bundle: .module).textStyle(.editorCancel).foregroundStyle(ColorToken.textPrimary.color)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("export.cancel")
            } title: {
                Text("Export \(model.ids.count) moments", bundle: .module)
                    .textStyle(.editorTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(minHeight: Size.minimumTapTarget)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SegmentedControl(selection: $model.archive, options: [false, true]) { archive in
                        archive ? Text("One archive (.zip)", bundle: .module) : Text("Separate files", bundle: .module)
                    }
                    .accessibilityIdentifier("export.kind")
                    DataNote(text: kindNote)
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                    Text("Include", bundle: .module)
                        .textStyle(.labelCaps)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 6)
                        .padding(.top, 20)
                    DataCard {
                        DataToggleRow(title: Text("Voice notes", bundle: .module), isOn: $model.options.voiceNotes)
                            .accessibilityIdentifier("export.voice")
                        DataSeparator()
                        DataToggleRow(title: Text("Notes", bundle: .module), isOn: $model.options.notes)
                            .accessibilityIdentifier("export.notes")
                        DataSeparator()
                        DataToggleRow(
                            title: Text("Original camera files", bundle: .module), detail: Text("front and back separately", bundle: .module),
                            isOn: $model.options.originals
                        )
                        .accessibilityIdentifier("export.originals")
                        DataSeparator()
                        DataToggleRow(title: Text("Exact places", bundle: .module), isOn: $model.options.exactPlace)
                            .accessibilityIdentifier("export.places")
                    }
                    .padding(.top, 4)
                    DataNote(text: sizeNote).padding(.horizontal, 6).padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 5)
            }
            Button { Task { sharing = await model.files() } } label: {
                if let progress = model.progress {
                    Text("Exporting \(progress.formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.shared.locale)))", bundle: .module)
                } else {
                    Text("Export", bundle: .module)
                }
            }
            .buttonStyle(.primary)
            .disabled(model.progress != nil || model.ids.isEmpty)
            .accessibilityIdentifier("export.start")
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil; model.removeFiles(); close() } })) {
            ShareSheet(items: sharing ?? [])
        }
        .exportFailureAlert(model)
    }

    private var kindNote: Text {
        model.archive
            ? Text("An archive keeps everything together with a list of dates, notes and places that any computer can read.", bundle: .module)
            : Text("Each moment as its own files, named by the date and time it was taken.", bundle: .module)
    }

    /// "About 240 MB · 12 GB free".
    private var sizeNote: Text {
        let size = StorageView.bytes(model.estimatedBytes)
        guard let free = model.available else { return Text("About \(size).", bundle: .module) }
        return Text("About \(size) · \(StorageView.bytes(free)) free", bundle: .module)
    }
}

private extension View {
    func exportFailureAlert(_ model: MomentExportModel) -> some View {
        alert(
            Text("Couldn't export", bundle: .module),
            isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
        ) {
            Button { model.failure = nil } label: { Text("OK", bundle: .module) }
        } message: {
            switch model.failure {
            case let .space(needed):
                Text("There isn't enough free space on this iPhone. It needs about \(StorageView.bytes(needed)) more.", bundle: .module)
            default:
                Text("Something went wrong. Try again.", bundle: .module)
            }
        }
    }
}

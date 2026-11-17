import Core
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

struct BackupScreen: View {
    /// The page it was opened from.
    var back = Text("Settings", bundle: .module)
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library { BackupHost(model: BackupModel(library: library), library: library, back: back) }
    }
}

private struct BackupHost: View {
    @State var model: BackupModel
    let library: MediaLibrary
    let back: Text
    @State private var backingUp = false
    @State private var choosingBackup = false
    @State private var restoring: URL?

    var body: some View {
        BackupView(model: model, back: back, backUp: {
            model.reset()
            backingUp = true
        }, restore: { choosingBackup = true })
        .onAppear { model.refresh() }
        .navigationDestination(isPresented: $backingUp) {
            BackupFlowView(model: model) { backingUp = false }
        }
        .navigationDestination(item: $restoring) { url in
            RestoreScreen(url: url, library: library) { restoring = nil }
        }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.data]) { result in
            if case let .success(url) = result { restoring = url }
        }
    }
}

/// E06: when the last backup was made and what isn't in one yet; back up now, restore, and the reminder.
struct BackupView: View {
    @Bindable var model: BackupModel
    /// The page it was opened from.
    var back = Text("Settings", bundle: .module)
    let backUp: () -> Void
    let restore: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: back) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Backup", bundle: .module)
                        .textStyle(.pageTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    statusCard
                        .padding(.horizontal, 16)
                        .padding(.top, 13)
                    Button(action: backUp) { Text("Back up now", bundle: .module) }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("backup.now")
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                    DataCard {
                        Button(action: restore) {
                            DataIconRow(icon: .glyphRefresh, title: Text("Restore from a backup", bundle: .module))
                        }
                        .accessibilityIdentifier("backup.restore")
                        DataSeparator(leading: 64)
                        Menu {
                            Picker(selection: $model.reminder) {
                                ForEach(BackupReminder.allCases, id: \.self) { $0.title.tag($0) }
                            } label: { EmptyView() }
                        } label: {
                            DataIconRow(icon: .glyphBell, title: Text("Remind me to back up", bundle: .module), value: model.reminder.title)
                        }
                        .accessibilityIdentifier("backup.reminder")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    DataNote(text: Text(
                        "Backups are files you keep. MimoDays never uploads them anywhere. If this iPhone is lost, a backup is the only way to get your moments back.",
                        bundle: .module
                    ))
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                }
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// `Card / Last backup`: a clock on peach, when, and what only this iPhone has.
    private var statusCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Icon.glyphClock.image
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(ColorToken.accentPeach.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                title.textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
                if let warning {
                    warning
                        .textStyle(TextStyle(.nunito, size: 13.5, weight: 600, relativeTo: .footnote))
                        .foregroundStyle(model.newSince > 0 ? ColorToken.textDestructive.color : ColorToken.textSecondary.color)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 0)
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(InfoCardBlob().fill(ColorToken.surfaceCard.color))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("backup.status")
    }

    private var title: Text {
        guard let last = model.last else { return Text("No backup yet", bundle: .module) }
        return Text("Last backup \(DataFormat.ago(last, now: .now))", bundle: .module)
    }

    private var warning: Text? {
        if model.last == nil {
            return model.newSince > 0 ? Text("\(model.newSince) moments are only on this iPhone.", bundle: .module) : nil
        }
        return model.newSince > 0
            ? Text("\(model.newSince) new moments since then are only on this iPhone.", bundle: .module)
            : Text("Every moment is in it.", bundle: .module)
    }
}

extension BackupReminder {
    var title: Text {
        switch self {
        case .never: Text("Never", bundle: .module)
        case .weekly: Text("Weekly", bundle: .module)
        case .monthly: Text("Monthly", bundle: .module)
        }
    }
}

/// E03 -> E04p -> E04 (or the failure) for one backup.
struct BackupFlowView: View {
    let model: BackupModel
    let close: () -> Void
    @State private var choosing = false
    /// The chosen place couldn't take the file (offline drive, no room there): the backup stays packed to choose again.
    @State private var notSaved = false

    var body: some View {
        Group {
            switch model.phase {
            case .options:
                BackupOptionsView(model: model, back: close)
            case let .working(step, progress):
                BackupProgressView(step: step, progress: progress, moments: model.contents.moments) {
                    model.cancel()
                } choose: { choosing = true }
            case let .saved(saved):
                BackupSavedView(saved: saved, done: close)
            case let .failed(failure):
                BackupFailedView(failure: failure, back: model.reset)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: model.phase) { _, phase in
            if case .working(.choosing, _) = phase { choosing = true }
        }
        .fileMover(isPresented: $choosing, file: model.packed) { result in
            switch result {
            case let .success(url): model.saved(to: url)
            case let .failure(error): notSaved = (error as? CocoaError)?.code != .userCancelled
            }
        }
        .alert(Text("The backup wasn't saved", bundle: .module), isPresented: $notSaved) {
            Button { choosing = true } label: { Text("Choose another place", bundle: .module) }
            Button(role: .cancel) {} label: { Text("Not now", bundle: .module) }
        } message: {
            Text("That place couldn't take the file. Nothing was changed.", bundle: .module)
        }
        .onDisappear { if case .working = model.phase { model.cancel() } }
    }
}

/// E03: what goes in and how big it is; rendered movies are optional because projects can make them again.
struct BackupOptionsView: View {
    @Bindable var model: BackupModel
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Backup", bundle: .module), action: back)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Back up everything", bundle: .module)
                        .textStyle(.pageTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 4)
                    Text(
                        "One file with every moment, note, voice note, collection and movie project. Keep it in Files, on a Mac or on a drive. It can be restored on any iPhone with MimoDays.",
                        bundle: .module
                    )
                    .textStyle(.sheetBody)
                    .foregroundStyle(ColorToken.textBody.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
                }
                .padding(.horizontal, 20)
                VStack(alignment: .leading, spacing: 0) {
                    DataCard {
                        sizeRow(Text("Moments, notes and voice", bundle: .module), model.contents.momentBytes)
                        DataSeparator()
                        sizeRow(Text("Movie projects", bundle: .module), model.contents.projectBytes)
                        DataSeparator()
                        DataToggleRow(
                            title: Text("Rendered movies", bundle: .module), detail: Text("can be made again from projects", bundle: .module),
                            isOn: $model.includesRenders
                        )
                        .accessibilityIdentifier("backup.renders")
                    }
                    .padding(.top, 24)
                    DataNote(text: sizeNote).padding(.horizontal, 6).padding(.top, 16)
                }
                .padding(.horizontal, 16)
            }
            Button(action: model.start) { Text("Create backup", bundle: .module) }
                .buttonStyle(.primary)
                .accessibilityIdentifier("backup.create")
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }

    private func sizeRow(_ title: Text, _ bytes: Int64) -> some View {
        HStack {
            title.textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
            Spacer(minLength: 8)
            Text(StorageView.bytes(bytes)).textStyle(.rowValue).foregroundStyle(ColorToken.textTertiary.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    /// "About 5.2 GB · 12 GB free".
    private var sizeNote: Text {
        let size = StorageView.bytes(model.estimatedBytes)
        guard let free = model.available else { return Text("About \(size).", bundle: .module) }
        return Text("About \(size) · \(StorageView.bytes(free)) free", bundle: .module)
    }
}

/// E04p: the four steps, the one under way with how far it got.
struct BackupProgressView: View {
    let step: BackupModel.Step
    let progress: Double
    let moments: Int
    let cancel: () -> Void
    let choose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ExplainerArt(glyph: .explainerArchive).padding(.top, 96)
                    Text("Creating your backup", bundle: .module)
                        .textStyle(.emptyTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 14)
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(BackupModel.Step.allCases, id: \.self) { item in
                            StepRow(state: item < step ? .done : item == step ? .now : .toDo, title: title(item))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.top, 26)
                    Text("Keep MimoDays open. If you leave, the backup pauses and continues when you come back.", bundle: .module)
                        .textStyle(.sheetBody)
                        .foregroundStyle(ColorToken.textBody.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 36)
                        .padding(.top, 40)
                }
            }
            if step == .choosing {
                Button(action: choose) { Text("Choose where to save", bundle: .module) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("backup.choose")
                    .padding(.horizontal, 20)
            }
            Button(action: cancel) { Text("Cancel", bundle: .module) }
                .buttonStyle(.text)
                .accessibilityIdentifier("backup.cancel")
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
    }

    private func title(_ item: BackupModel.Step) -> Text {
        switch item {
        case .collecting: Text("Collecting \(moments) moments", bundle: .module)
        case .packing:
            item == step
                ? Text("Packing files · \(progress.formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.shared.locale)))", bundle: .module)
                : Text("Packing files", bundle: .module)
        case .checking: Text("Checking the backup", bundle: .module)
        case .choosing: Text("Choosing where to save", bundle: .module)
        }
    }
}

/// `Step / Done`, `Step / Now`, `Step / To do`.
struct StepRow: View {
    enum State { case done, now, toDo }
    let state: State
    let title: Text

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                switch state {
                case .done:
                    Circle().fill(ColorToken.actionCoral.color)
                    Icon.glyphCheck.image.resizable().frame(width: 16, height: 16).foregroundStyle(ColorToken.textOnCoral.color)
                case .now:
                    Circle().fill(ColorToken.accentPeach.color)
                    Circle().strokeBorder(ColorToken.actionCoral.color, lineWidth: 2)
                    Circle().fill(ColorToken.actionCoral.color).frame(width: 8, height: 8)
                case .toDo:
                    Circle().strokeBorder(Color(hex: 0xCDBFB4), lineWidth: 2)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            title
                .textStyle(TextStyle(.nunito, size: 15, weight: state == .now ? 800 : state == .done ? 700 : 600, relativeTo: .subheadline))
                .foregroundStyle((state == .toDo ? ColorToken.textTertiary : ColorToken.textPrimary).color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == .done ? Text("Done", bundle: .module) : state == .now ? Text("In progress", bundle: .module) : Text(verbatim: ""))
    }
}

/// E04: what was packed, checked and where it went.
struct BackupSavedView: View {
    let saved: BackupModel.Saved
    let done: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ExplainerArt(glyph: .explainerCheck, blob: .accentMint).padding(.top, 96)
                    Text("Backup saved", bundle: .module)
                        .textStyle(.emptyTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 14)
                    Text(verbatim: "\(saved.url.lastPathComponent) · \(StorageView.bytes(saved.bytes))")
                        .textStyle(TextStyle(.nunito, size: 13.5, weight: 600, relativeTo: .footnote))
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 18) {
                        StepRow(state: .done, title: Text("\(saved.moments) moments packed", bundle: .module))
                        StepRow(state: .done, title: Text("Every file checked and readable", bundle: .module))
                        StepRow(state: .done, title: Text("Saved to Files › \(saved.url.deletingLastPathComponent().lastPathComponent)", bundle: .module))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.top, 33)
                }
            }
            VStack(spacing: 16) {
                Button {
                    if let url = URL(string: "shareddocuments://" + saved.url.deletingLastPathComponent().path) { openURL(url) }
                } label: {
                    Label { Text("Show in Files", bundle: .module) } icon: { Icon.glyphFolder.image.resizable().frame(width: 20, height: 20) }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("backup.showInFiles")
                Button(action: done) { Text("Done", bundle: .module) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("backup.done")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}

/// No room to pack it, or something else stopped it; nothing was saved.
struct BackupFailedView: View {
    let failure: BackupModel.Failure
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ExplainerArt(glyph: .explainerWarning, ink: .textLink).padding(.top, 96)
                    Text("The backup couldn't be made", bundle: .module)
                        .textStyle(.emptyTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    message
                        .textStyle(.sheetBody)
                        .foregroundStyle(ColorToken.textBody.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 44)
                        .padding(.top, 12)
                }
            }
            Button(action: back) { Text("Back", bundle: .module) }
                .buttonStyle(.primary)
                .accessibilityIdentifier("backup.back")
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }

    private var message: Text {
        switch failure {
        case let .space(needed):
            Text("There isn't enough free space on this iPhone to make it. It needs about \(StorageView.bytes(needed)) more.", bundle: .module)
        case .other:
            Text("Something went wrong while packing it. Nothing was changed. Try again.", bundle: .module)
        }
    }
}

import Core
import DesignSystem
import SwiftUI

struct RestoreScreen: View {
    let url: URL
    let library: MediaLibrary
    let close: () -> Void
    @State private var model: RestoreModel?

    var body: some View {
        Group {
            if let model { RestoreView(model: model, close: close) }
        }
        .onAppear {
            guard model == nil else { return }
            let model = RestoreModel(url: url, library: library)
            self.model = model
            model.start()
        }
    }
}

/// E07, E08 and the cases on E08's note: not a backup, from a newer MimoDays, not enough room.
struct RestoreView: View {
    @Bindable var model: RestoreModel
    let close: () -> Void
    @State private var showsSkipped = false
    @State private var exportInUse = false
    @State private var shrinkInUse = false
    @Environment(MovieExportCenter.self) private var exports: MovieExportCenter?
    @Environment(ShrinkRun.self) private var shrinks: ShrinkRun?

    var body: some View {
        VStack(spacing: 0) {
            bar
            switch model.phase {
            case let .checking(progress):
                working(Text("Checking the backup", bundle: .module), progress: progress)
            case let .ready(summary):
                ready(summary)
            case let .restoring(progress):
                working(Text("Restoring your moments", bundle: .module), progress: progress)
            case let .done(outcome):
                done(outcome)
            case let .failed(failure):
                failed(failure)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsSkipped) { skippedList }
        .exportInUseAlert($exportInUse)
        .shrinkInUseAlert($shrinkInUse)
        .onDisappear { if case .restoring = model.phase {} else { model.cancel() } }
    }

    /// `Navigation / Editor bar`: Cancel until it's done, then Done.
    private var bar: some View {
        TitleBar {
            if !isFinished {
                Button {
                    model.cancel()
                    close()
                } label: {
                    Text("Cancel", bundle: .module).textStyle(.editorCancel).foregroundStyle(ColorToken.textBody.color)
                        .padding(.horizontal, 16).frame(minHeight: Size.minimumTapTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)
                .accessibilityIdentifier("restore.cancel")
            }
        } title: {
            Text("Restore", bundle: .module)
                .textStyle(.editorTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
        } trailing: {
            if isFinished {
                Button(action: close) {
                    Text("Done", bundle: .module).textStyle(.editorDone).foregroundStyle(ColorToken.textLink.color)
                        .padding(.horizontal, 16).frame(minHeight: Size.minimumTapTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("restore.done")
            }
        }
        .frame(height: 44)
    }

    private var isRestoring: Bool { if case .restoring = model.phase { true } else { false } }
    private var isFinished: Bool {
        switch model.phase {
        case .done, .failed: true
        default: false
        }
    }

    private func working(_ title: Text, progress: Double) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ExplainerArt(glyph: .explainerArchive)
            title.textStyle(.largeSheetTitle).foregroundStyle(ColorToken.textPrimary.color)
            ProgressView(value: progress)
                .tint(ColorToken.actionCoral.color)
                .padding(.horizontal, 60)
                .accessibilityIdentifier("restore.progress")
            Spacer()
            Spacer()
        }
    }

    // MARK: E07

    private func ready(_ summary: BackupService.Summary) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    backupCard(summary)
                    Text(alreadyLine(summary))
                        .textStyle(.rowTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                        .padding(.top, 20)
                    DataCard {
                        choice(.addMissing, Text("Add what's missing", bundle: .module), Text("Nothing here is changed or removed", bundle: .module))
                        DataSeparator()
                        choice(.replaceEverything, Text("Replace everything", bundle: .module), Text("This iPhone will match the backup exactly", bundle: .module))
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            Button {
                // P8.13: Replace everything removes files the running export reads.
                if model.mode == .replaceEverything, exports?.isExporting == true {
                    exportInUse = true
                } else if model.mode == .replaceEverything, shrinks?.isRunning == true {
                    shrinkInUse = true
                } else {
                    model.restore()
                }
            } label: { restoreLabel(summary) }
                .buttonStyle(.primary)
                .disabled(!model.canRestore)
                .accessibilityIdentifier("restore.start")
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }

    private func backupCard(_ summary: BackupService.Summary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Icon.glyphArchive.image
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(ColorToken.accentPeach.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Backup from \(summary.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLanguage.shared.locale)))", bundle: .module)
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Text(Self.contents(summary))
                    .textStyle(.meta)
                    .foregroundStyle(ColorToken.textSecondary.color)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(InfoCardBlob().fill(ColorToken.surfaceCard.color))
        .accessibilityElement(children: .combine)
    }

    /// "1,140 moments · 6 collections · 3 movie projects · checked, no problems".
    static func contents(_ summary: BackupService.Summary) -> String {
        let check = summary.isClean
            ? String(appLocalized: "checked, no problems", bundle: .module, comment: "Restore (E07): the backup was read and every file matched")
            : String(appLocalized: "some files are damaged", bundle: .module, comment: "Restore (E07): the backup was read and some files didn't match")
        return String(
            localized: "\(summary.moments) moments · \(summary.collections) collections · \(summary.projects) movie projects · \(check)", bundle: .module,
            comment: "Restore (E07): what the backup holds, then how its check went"
        )
    }

    private func alreadyLine(_ summary: BackupService.Summary) -> String {
        String(
            localized: "\(summary.alreadyHere) are already here. \(summary.new) are new.", bundle: .module,
            comment: "Restore (E07): how many of the backup's moments this iPhone has, and how many it doesn't"
        )
    }

    private func restoreLabel(_ summary: BackupService.Summary) -> Text {
        model.mode == .addMissing
            ? (model.adding == 0 ? Text("Add what's missing", bundle: .module) : Text("Add \(model.adding) moments", bundle: .module))
            : Text("Replace with \(model.adding) moments", bundle: .module)
    }

    private func choice(_ mode: BackupService.Mode, _ title: Text, _ detail: Text) -> some View {
        Button { model.mode = mode } label: {
            HStack {
                DataRowLabel(title: title, detail: detail)
                Spacer(minLength: 8)
                if model.mode == mode {
                    Icon.glyphCheck.image.resizable().frame(width: 22, height: 22).foregroundStyle(ColorToken.actionCoral.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(model.mode == mode ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(mode == .addMissing ? "restore.add" : "restore.replace")
    }

    // MARK: E08

    private func done(_ outcome: BackupService.Outcome) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ExplainerArt(
                    glyph: outcome.damagedFiles > 0 ? .explainerWarning : .explainerCheck,
                    blob: outcome.damagedFiles > 0 ? .accentPeach : .accentMint,
                    ink: outcome.damagedFiles > 0 ? .textLink : .textPrimary
                )
                .padding(.top, 6)
                Text("\(outcome.restored) of \(outcome.wanted) moments restored", bundle: .module)
                    .textStyle(.largeSheetTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
                if outcome.damagedFiles > 0 || outcome.alreadyHere > 0 {
                    DataCard {
                        if outcome.damagedFiles > 0 {
                            Button { showsSkipped = true } label: {
                                DataIconRow(
                                    icon: .glyphWarning, title: Text("\(outcome.damagedFiles) files are damaged", bundle: .module),
                                    detail: Text("Skipped. The rest of the backup is fine.", bundle: .module), iconInk: .textLink
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("restore.damaged")
                        }
                        if outcome.damagedFiles > 0, outcome.alreadyHere > 0 { DataSeparator(leading: 64) }
                        if outcome.alreadyHere > 0 {
                            DataIconRow(
                                icon: .glyphCheck, title: Text("\(outcome.alreadyHere) were already here", bundle: .module),
                                detail: Text("Left as they are", bundle: .module), opens: false
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 15)
                }
            }
        }
    }

    private var skippedList: some View {
        NavigationStack {
            List {
                if case let .done(outcome) = model.phase {
                    ForEach(outcome.skipped, id: \.self) { date in
                        Text(date.formatted(Date.FormatStyle(date: .complete, time: .shortened).locale(AppLanguage.shared.locale)))
                    }
                }
            }
            .navigationTitle(Text("Skipped moments", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showsSkipped = false } label: { Text("Done", bundle: .module) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Failures

    private func failed(_ failure: RestoreModel.Failure) -> some View {
        VStack(spacing: 0) {
            ExplainerArt(glyph: .explainerWarning, ink: .textLink).padding(.top, 6)
            failureTitle(failure)
                .textStyle(.largeSheetTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            failureMessage(failure)
                .textStyle(.sheetBody)
                .foregroundStyle(ColorToken.textBody.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 44)
                .padding(.top, 10)
            Spacer()
        }
        .accessibilityIdentifier("restore.failed")
    }

    private func failureTitle(_ failure: RestoreModel.Failure) -> Text {
        switch failure {
        case .notABackup: Text("This isn't a MimoDays backup", bundle: .module)
        case .newerVersion: Text("Update MimoDays first", bundle: .module)
        case .space: Text("Not enough space", bundle: .module)
        case .other: Text("The backup couldn't be restored", bundle: .module)
        }
    }

    private func failureMessage(_ failure: RestoreModel.Failure) -> Text {
        switch failure {
        case .notABackup:
            Text("Choose a .mimodays file made with Back up now. A file that was cut off while copying can't be read either.", bundle: .module)
        case .newerVersion:
            Text("This backup was made by a newer MimoDays. Update the app, then restore it.", bundle: .module)
        case let .space(needed):
            Text("Nothing was restored. This iPhone needs about \(StorageView.bytes(needed)) more free space.", bundle: .module)
        case .other:
            Text("Nothing on this iPhone was changed. Try again.", bundle: .module)
        }
    }
}

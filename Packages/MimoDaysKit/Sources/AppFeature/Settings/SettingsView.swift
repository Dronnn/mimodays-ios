import Core
import DesignSystem
import Persistence
import SwiftUI

/// Where S01's rows lead.
enum SettingsRoute: Hashable {
    case surprises
}

/// The Settings sheet: S01 and everything under it.
struct SettingsScreen: View {
    let surprises: SurpriseCoordinator?
    @Environment(\.mediaLibrary) private var library
    @Environment(\.permissions) private var permissions

    var body: some View {
        if let library {
            SettingsHost(model: SettingsModel(library: library, surprises: surprises, permissions: permissions))
        }
    }
}

private struct SettingsHost: View {
    @State var model: SettingsModel
    @State private var path = NavigationPath()
    @State private var importsPhotos = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            SettingsView(model: model, importPhotos: { importsPhotos = true }, done: { dismiss() })
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .surprises: SurpriseSettingsView(model: model).toolbar(.hidden, for: .navigationBar)
                    }
                }
                .navigationDestination(for: DataRoute.self) { route in
                    switch route {
                    case .storage: StorageScreen()
                    case .backup: BackupScreen()
                    case .recentlyDeleted: RecentlyDeletedScreen()
                    }
                }
        }
        .photoImport(isPresented: $importsPhotos)
        .task { await model.load() }
        .onChange(of: path.count) { _, count in
            // Back on S01: Storage, Backup or Surprises may have changed what it says.
            if count == 0 { Task { await model.load() } }
        }
    }
}

/// S01: everything MimoDays lets you change, in four cards.
struct SettingsView: View {
    let model: SettingsModel
    let importPhotos: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: done) {
                    Text("Done", bundle: .module).textStyle(.editorDone).foregroundStyle(ColorToken.textLink.color)
                }
                .buttonStyle(.plain)
                .frame(minHeight: Size.minimumTapTarget)
                .accessibilityIdentifier("settings.done")
            }
            .padding(.horizontal, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings", bundle: .module)
                        .textStyle(TextStyle(.fraunces, size: 34, weight: 600, relativeTo: .largeTitle, maximumScale: 1.35))
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 4)
                        .padding(.bottom, -3)
                    DataCard {
                        link(SettingsRoute.surprises, .glyphBell, Text("Surprises", bundle: .module), value: surprisesValue, id: "settings.surprises")
                    }
                    DataCard {
                        link(DataRoute.storage, .glyphFolder, Text("Storage", bundle: .module), value: model.storageBytes.map { Text(StorageView.bytes($0)) }, id: "settings.storage")
                        DataSeparator(leading: 64)
                        link(DataRoute.backup, .glyphArchive, Text("Backup", bundle: .module), value: backupValue, id: "settings.backup")
                        DataSeparator(leading: 64)
                        Button(action: importPhotos) {
                            DataIconRow(icon: .glyphPhotos, title: Text("Import from Photos", bundle: .module))
                        }
                        .accessibilityIdentifier("settings.import")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private func link(_ route: some Hashable, _ icon: Icon, _ title: Text, value: Text? = nil, id: String) -> some View {
        NavigationLink(value: route) { DataIconRow(icon: icon, title: title, value: value) }
            .accessibilityIdentifier(id)
    }

    /// "Once a day", "Paused" or "Off".
    private var surprisesValue: Text {
        guard model.surprisesOn else { return Text("Off", bundle: .module) }
        guard model.pause == .off else { return Text("Paused", bundle: .module) }
        return Text(model.reminders.frequency.label)
    }

    /// "18 days ago", or "Never".
    private var backupValue: Text {
        guard let last = model.lastBackup else { return Text("Never", bundle: .module) }
        return Text(DataFormat.ago(last, now: .now))
    }
}

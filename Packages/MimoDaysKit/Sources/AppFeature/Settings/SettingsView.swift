import Core
import DesignSystem
import Persistence
import SwiftUI

/// Where S01's rows lead.
enum SettingsRoute: Hashable {
    case surprises
    case camera
    case memories
    case movies
    case privacy
    case appearance
    case donations
    case help
    case helpArticle(HelpArticle)
    /// S05 "How MimoDays uses your data", from Privacy or Help.
    case dataUse(back: SettingsBack)
    /// S08.
    case deleteAll
}

/// What the back button says on a page opened from more than one place: the page it goes back to.
enum SettingsBack: Hashable {
    case settings
    case privacy
    case help
    case storage
    /// S08, whose title is a question: a plain "Back".
    case deleteAll

    var label: Text {
        switch self {
        case .settings: Text("Settings", bundle: .module)
        case .privacy: Text("Privacy", bundle: .module)
        case .help: Text("Help & about", bundle: .module)
        case .storage: Text("Storage", bundle: .module)
        case .deleteAll: Text("Back", bundle: .module)
        }
    }
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
                .settingsPage()
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .surprises: SurpriseSettingsView(model: model).settingsPage()
                    case .camera: CameraSettingsScreen().settingsPage()
                    case .memories: MemoriesSettingsScreen().settingsPage()
                    case .movies: MovieSettingsScreen().settingsPage()
                    case .privacy: PrivacySettingsScreen().settingsPage()
                    case .appearance: AppearanceSettingsScreen().settingsPage()
                    case .donations: DonationsScreen().settingsPage()
                    case .help: HelpView().settingsPage()
                    case let .helpArticle(article): HelpArticleView(article: article).settingsPage()
                    case let .dataUse(back): DataUseView(back: back.label).settingsPage()
                    case .deleteAll: DeleteAllScreen().settingsPage()
                    }
                }
                .navigationDestination(for: DataRoute.self) { route in
                    switch route {
                    case .storage: StorageScreen().settingsPage()
                    case let .backup(back): BackupScreen(back: back.label).settingsPage()
                    case .recentlyDeleted: RecentlyDeletedScreen().settingsPage()
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

private extension View {
    /// A Settings page draws its own bar; a sheet has no top inset, so the bar keeps this room from the sheet's
    /// rounded top edge (Andrew, 2026-11-16).
    func settingsPage() -> some View {
        toolbar(.hidden, for: .navigationBar).safeAreaPadding(.top, 16)
    }
}

/// S01: everything MimoDays lets you change, in four cards.
struct SettingsView: View {
    let model: SettingsModel
    let importPhotos: () -> Void
    let done: () -> Void
    @Environment(AppearancePreferences.self) private var appearance: AppearancePreferences?

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
                        DataSeparator(leading: 64)
                        link(SettingsRoute.camera, .glyphCamera, Text("Camera", bundle: .module), id: "settings.camera")
                        DataSeparator(leading: 64)
                        link(SettingsRoute.memories, .glyphCollection, Text("Memories", bundle: .module), id: "settings.memories")
                        DataSeparator(leading: 64)
                        link(SettingsRoute.movies, .glyphFilm, Text("Movies & export", bundle: .module), id: "settings.movies")
                    }
                    DataCard {
                        link(SettingsRoute.privacy, .glyphLock, Text("Privacy & App Lock", bundle: .module), id: "settings.privacy")
                        DataSeparator(leading: 64)
                        link(SettingsRoute.appearance, .glyphMoon, Text("Appearance", bundle: .module), value: appearanceValue, id: "settings.appearance")
                    }
                    DataCard {
                        link(DataRoute.storage, .glyphFolder, Text("Storage", bundle: .module), value: model.storageBytes.map { Text(StorageView.bytes($0)) }, id: "settings.storage")
                        DataSeparator(leading: 64)
                        link(DataRoute.backup(back: .settings), .glyphArchive, Text("Backup", bundle: .module), value: backupValue, id: "settings.backup")
                        DataSeparator(leading: 64)
                        Button(action: importPhotos) {
                            DataIconRow(icon: .glyphPhotos, title: Text("Import from Photos", bundle: .module))
                        }
                        .accessibilityIdentifier("settings.import")
                    }
                    DataCard {
                        link(SettingsRoute.donations, .glyphHeart, Text("Donations", bundle: .module), id: "settings.donations")
                        DataSeparator(leading: 64)
                        link(SettingsRoute.help, .glyphHelp, Text("Help & about", bundle: .module), id: "settings.help")
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

    /// "System", "Light" or "Dark".
    private var appearanceValue: Text {
        switch appearance?.value.appearance ?? .system {
        case .system: Text("System", bundle: .module)
        case .light: Text("Light", bundle: .module)
        case .dark: Text("Dark", bundle: .module)
        }
    }

    /// "18 days ago", or "Never".
    private var backupValue: Text {
        guard let last = model.lastBackup else { return Text("Never", bundle: .module) }
        return Text(DataFormat.ago(last, now: .now))
    }
}

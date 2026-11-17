import DesignSystem
import SwiftUI

/// S05 with the app's preferences, App Lock and the library.
struct PrivacySettingsScreen: View {
    @Environment(PrivacyPreferences.self) private var preferences: PrivacyPreferences?
    @Environment(AppLock.self) private var lock: AppLock?
    @Environment(\.mediaLibrary) private var library
    @State private var placeCount = 0

    var body: some View {
        if let preferences, let lock, let library {
            @Bindable var preferences = preferences
            PrivacySettingsView(
                settings: $preferences.value,
                biometry: lock.biometry,
                placeCount: placeCount,
                turnOnLock: {
                    await lock.confirm(String(localized: "Turn on App Lock", bundle: .module, comment: "Why Face ID is asked for: to turn App Lock on"))
                },
                removePlaces: {
                    do {
                        try PlaceEraser.removeAll(library.context)
                    } catch {
                        library.context.rollback()
                    }
                    placeCount = PlaceEraser.count(library.context)
                }
            )
            .onAppear { placeCount = PlaceEraser.count(library.context) }
        }
    }
}

/// S05: App Lock, what a moment keeps of where you were, and the way to the privacy statement and Delete all data.
struct PrivacySettingsView: View {
    @Binding var settings: PrivacySettings
    let biometry: AppLock.Biometry
    let placeCount: Int
    let turnOnLock: () async -> Bool
    let removePlaces: () -> Void
    @State private var confirmsRemoval = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Settings", bundle: .module), title: Text("Privacy", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel(Text("App Lock", bundle: .module))
                    DataCard {
                        DataToggleRow(title: Text("Lock with \(biometry.name)", bundle: .module, comment: "S05's App Lock switch, e.g. 'Lock with Face ID'"), isOn: lockBinding)
                            .accessibilityIdentifier("privacySettings.appLock")
                        DataSeparator()
                        Menu {
                            Picker(selection: $settings.lockAfter) {
                                ForEach(PrivacySettings.LockDelay.allCases, id: \.self) { $0.title.tag($0) }
                            } label: {
                                Text("Lock after", bundle: .module)
                            }
                        } label: {
                            SettingsValueRow(title: Text("Lock after", bundle: .module), value: settings.lockAfter.title)
                        }
                        .accessibilityIdentifier("privacySettings.lockAfter")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    DataNote(text: Text(
                        "Recently deleted always asks for \(biometry.name) when App Lock is on.", bundle: .module,
                        comment: "S05's note under App Lock, e.g. '…asks for Face ID…'"
                    ))
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    sectionLabel(Text("Places", bundle: .module))
                        .padding(.top, 26)
                    DataCard {
                        DataToggleRow(title: Text("Save a place with moments", bundle: .module), isOn: $settings.savesPlace)
                            .accessibilityIdentifier("privacySettings.savesPlace")
                        DataSeparator()
                        Menu {
                            Picker(selection: $settings.precision) {
                                ForEach(PrivacySettings.PlacePrecision.allCases, id: \.self) { $0.title.tag($0) }
                            } label: {
                                Text("Precision", bundle: .module)
                            }
                        } label: {
                            SettingsValueRow(title: Text("Precision", bundle: .module), value: settings.precision.title)
                        }
                        .accessibilityIdentifier("privacySettings.precision")
                        DataSeparator()
                        Button { confirmsRemoval = true } label: {
                            Text("Remove all places…", bundle: .module)
                                .textStyle(.rowTitle)
                                .foregroundStyle(ColorToken.textLink.color)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, minHeight: Size.rowHeight, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .disabled(placeCount == 0)
                        .opacity(placeCount == 0 ? 0.5 : 1)
                        .accessibilityIdentifier("privacySettings.removePlaces")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    DataCard {
                        NavigationLink(value: SettingsRoute.dataUse) {
                            DataIconRow(icon: .glyphInfo, title: Text("How MimoDays uses your data", bundle: .module))
                        }
                        .accessibilityIdentifier("privacySettings.dataUse")
                        DataSeparator(leading: 64)
                        NavigationLink(value: SettingsRoute.deleteAll) {
                            DataIconRow(
                                icon: .glyphTrash,
                                title: Text(String(localized: "Privacy row: delete all data", defaultValue: "Delete all data…", bundle: .module, comment: "Privacy settings (S05): row that opens Delete all data")),
                                titleColor: .textLink
                            )
                        }
                        .accessibilityIdentifier("privacySettings.deleteAll")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    DataNote(text: Text("Everything stays on this iPhone. No account, no ads, no tracking, no analytics.", bundle: .module))
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .confirmationDialog(
            Text("Remove the place from \(placeCount) moments?", bundle: .module, comment: "S05's confirmation before every moment's place goes"),
            isPresented: $confirmsRemoval, titleVisibility: .visible
        ) {
            Button(role: .destructive, action: removePlaces) { Text("Remove places", bundle: .module) }
        } message: {
            Text("The moments stay. This can't be undone.", bundle: .module)
        }
    }

    /// Turning App Lock on asks for Face ID first, so nobody locks themselves out.
    private var lockBinding: Binding<Bool> {
        Binding {
            settings.appLock
        } set: { isOn in
            guard isOn else {
                settings.appLock = false
                return
            }
            Task { if await turnOnLock() { settings.appLock = true } }
        }
    }

    private func sectionLabel(_ text: Text) -> some View {
        text.textStyle(.labelCaps)
            .foregroundStyle(ColorToken.textSecondary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 22)
    }
}

extension PrivacySettings.LockDelay {
    var title: Text {
        switch self {
        case .immediately: Text("Leaving the app", bundle: .module)
        case .oneMinute: Text("After 1 minute", bundle: .module)
        case .fifteenMinutes: Text("After 15 minutes", bundle: .module)
        case .oneHour: Text("After 1 hour", bundle: .module)
        }
    }
}

extension PrivacySettings.PlacePrecision {
    var title: Text {
        switch self {
        case .city: Text("City", bundle: .module)
        case .exact: Text("Exact", bundle: .module)
        }
    }
}

/// S05 "How MimoDays uses your data": the privacy statement, in plain words.
struct DataUseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Privacy", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("How MimoDays uses your data", bundle: .module)
                        .textStyle(.displaySheet)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .fixedSize(horizontal: false, vertical: true)
                    section(
                        Text("On this iPhone", bundle: .module),
                        Text("Your photos, videos, voice notes, notes, places, collections and movies are kept in MimoDays on this iPhone. There is no account and no MimoDays server.", bundle: .module)
                    )
                    section(
                        Text("Camera and microphone", bundle: .module),
                        Text("MimoDays uses them only while the camera is open or you record a voice note. A surprise never opens the camera by itself.", bundle: .module)
                    )
                    section(
                        Text("Places", bundle: .module),
                        Text("MimoDays checks where this iPhone is only while you're reviewing a capture or using the map, never in the background. To name the city, it asks Apple's map service. You can turn places off or remove them all.", bundle: .module)
                    )
                    section(
                        Text("Exports and backups", bundle: .module),
                        Text("Files leave MimoDays only when you share, export or back up. Exports leave out the exact place and voice notes unless you include them.", bundle: .module)
                    )
                    section(
                        Text("What MimoDays never does", bundle: .module),
                        Text("No ads, no tracking, no analytics, and nothing is sold or shared.", bundle: .module)
                    )
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private func section(_ title: Text, _ body: Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title.textStyle(.displaySection)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            body.textStyle(.body)
                .foregroundStyle(ColorToken.textBody.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 22)
    }
}

import DesignSystem
import Persistence
import SwiftUI

/// S06 with the app's preferences.
struct MovieSettingsScreen: View {
    @Environment(MoviePreferences.self) private var preferences: MoviePreferences?

    var body: some View {
        if let preferences {
            @Bindable var preferences = preferences
            MovieSettingsView(defaults: $preferences.value)
        }
    }
}

/// S06: the shape, length, captions and transitions a new movie starts with, and an export's quality and place.
struct MovieSettingsView: View {
    @Binding var defaults: MovieDefaults
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Settings", bundle: .module), title: Text("Movies & export", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel(Text("New movies start as", bundle: .module))
                    SegmentedControl(selection: $defaults.aspectRatio, options: MovieAspectRatio.allCases) { Text(verbatim: $0.label) }
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("movieSettings.shape")
                    DataCard {
                        Menu {
                            Picker(selection: $defaults.length) {
                                ForEach(MovieDefaults.lengths, id: \.self) { lengthTitle($0).tag($0) }
                            } label: {
                                Text("Length", bundle: .module)
                            }
                        } label: {
                            SettingsValueRow(title: Text("Length", bundle: .module), value: lengthTitle(defaults.length))
                        }
                        .accessibilityIdentifier("movieSettings.length")
                        DataSeparator()
                        DataToggleRow(title: Text("Date on clips", bundle: .module), isOn: $defaults.showsDates)
                            .accessibilityIdentifier("movieSettings.dates")
                        DataSeparator()
                        DataToggleRow(title: Text("Place on clips", bundle: .module), isOn: $defaults.showsPlaces)
                            .accessibilityIdentifier("movieSettings.places")
                        DataSeparator()
                        Menu {
                            Picker(selection: $defaults.transition) {
                                ForEach(MovieTransition.allCases, id: \.self) { transitionTitle($0).tag($0) }
                            } label: {
                                Text("Transitions", bundle: .module)
                            }
                        } label: {
                            SettingsValueRow(title: Text("Transitions", bundle: .module), value: transitionTitle(defaults.transition))
                        }
                        .accessibilityIdentifier("movieSettings.transition")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    sectionLabel(Text("Export", bundle: .module))
                        .padding(.top, 26)
                    DataCard {
                        Menu {
                            Picker(selection: $defaults.resolution) {
                                ForEach(MovieResolution.allCases, id: \.self) { $0.title.tag($0) }
                            } label: {
                                Text("Movie quality", bundle: .module)
                            }
                        } label: {
                            SettingsValueRow(title: Text("Movie quality", bundle: .module), value: defaults.resolution.title)
                        }
                        .accessibilityIdentifier("movieSettings.quality")
                        DataSeparator()
                        DataToggleRow(title: Text("Exact place in exported files", bundle: .module), isOn: $defaults.exactPlaceInFiles)
                            .accessibilityIdentifier("movieSettings.exactPlace")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    DataNote(text: Text("You can still change any of these for a single movie or export.", bundle: .module))
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private func sectionLabel(_ text: Text) -> some View {
        text.textStyle(.labelCaps)
            .foregroundStyle(ColorToken.textSecondary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 22)
    }

    private func lengthTitle(_ length: MovieLength) -> Text {
        switch length {
        case .quick: Text("Quick", bundle: .module)
        case .short: Text("Short", bundle: .module)
        case .full, .custom: Text("Full", bundle: .module)
        }
    }

    private func transitionTitle(_ transition: MovieTransition) -> Text {
        switch transition {
        case .cut: Text("Cut", bundle: .module)
        case .fade: Text("Fade", bundle: .module)
        }
    }
}

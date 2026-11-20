import Core
import DesignSystem
import SwiftUI

/// What the app shows: MimoDays, or, when its store can't be opened, a way back instead of a crash (Andrew,
/// 2026-11-20): try again, or set what's there aside and restore a backup into a new library.
public struct AppLaunchView: View {
    private let configuration: LaunchConfiguration
    /// Opened once, at launch, by the app.
    private let opened: AppDependencies?
    @State private var reopened: AppDependencies?
    /// The backup picked on the recovery screen, restored once the new library is open.
    @State private var restoring: URL?
    @State private var choosingBackup = false
    /// Try again didn't help, or setting aside failed.
    @State private var stillFails = false

    public init(configuration: LaunchConfiguration, opened: AppDependencies?) {
        self.configuration = configuration
        self.opened = opened
    }

    public var body: some View {
        if let dependencies = reopened ?? opened {
            RootView(dependencies: dependencies)
                .fullScreenCover(isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
                    if let restoring {
                        NavigationStack {
                            RestoreScreen(url: restoring, library: dependencies.library) { self.restoring = nil }
                        }
                    }
                }
        } else {
            StoreRecoveryView(stillFails: stillFails, tryAgain: tryAgain, restore: { choosingBackup = true })
                .appLanguage()
                .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.data]) { result in
                    if case let .success(url) = result { restore(from: url) }
                }
        }
    }

    private func tryAgain() {
        reopened = try? AppDependencies(configuration: configuration)
        stillFails = reopened == nil
    }

    /// The old store and media move aside, untouched; the backup goes into the new, empty library.
    private func restore(from url: URL) {
        do {
            try AppDependencies.setAside(configuration)
            let dependencies = try AppDependencies(configuration: configuration)
            // Someone who had moments has been through onboarding; the new library doesn't know it yet.
            let onboarding = SwiftDataOnboardingStore(context: dependencies.modelContainer.mainContext)
            var record = onboarding.load()
            record.isCompleted = true
            onboarding.save(record)
            reopened = dependencies
            restoring = url
        } catch {
            stillFails = true
        }
    }
}

/// The store couldn't be opened: nothing is deleted; Try again, or Restore from a backup.
struct StoreRecoveryView: View {
    let stillFails: Bool
    let tryAgain: () -> Void
    let restore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Centred, and scrolling once the largest text sizes need more room.
            GeometryReader { proxy in
                ScrollView {
                    message.frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            Button(action: tryAgain) { Text("Try again", bundle: .module) }
                .buttonStyle(.primary)
                .padding(.top, 12)
                .accessibilityIdentifier("recovery.tryAgain")
            Button(action: restore) { Text("Restore from a backup", bundle: .module) }
                .buttonStyle(.text)
                .padding(.top, 8)
                .accessibilityIdentifier("recovery.restore")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private var message: some View {
        VStack(spacing: 0) {
            Icon.glyphArchive.image
                .resizable()
                .frame(width: 30, height: 30)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: 88, height: 88)
                .background(Circle().fill(ColorToken.accentPeach.color))
                .accessibilityHidden(true)
            Text("Your moments couldn't be opened", bundle: .module, comment: "Launch: title when the library can't be opened (a damaged store); the app shows this instead of crashing")
                .textStyle(.displayHeadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 28)
            Text("Nothing has been deleted. Try again, or restore from a backup: what's here now is kept apart on this device.", bundle: .module, comment: "Launch: message under the title when the library can't be opened")
                .textStyle(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(ColorToken.textSecondary.color)
                .padding(.top, 10)
            if stillFails {
                Text("They still can't be opened.", bundle: .module, comment: "Launch: shown after Try again (or setting the library aside) failed again")
                    .textStyle(.body)
                    .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .padding(.top, 14)
                    .accessibilityIdentifier("recovery.stillFails")
            }
        }
        .padding(.vertical, 24)
    }
}

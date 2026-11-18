import DesignSystem
import MessageUI
import StoreKit
import SwiftUI
import UIKit

enum AppLinks {
    /// S07 "Send feedback": the same address as the site's Support page and the App Store listing.
    static let feedbackAddress = "mimodays@mrmaier.com"
    static let feedback = URL(string: "mailto:\(feedbackAddress)")
}

/// S07 "How it works": one short page each.
enum HelpArticle: String, CaseIterable, Hashable {
    case surprises
    case selfieWindow
    case permissions
    case newIPhone

    var title: Text {
        switch self {
        case .surprises: Text("Surprises", bundle: .module)
        case .selfieWindow: Text("The selfie window", bundle: .module)
        case .permissions: Text("Permissions", bundle: .module)
        case .newIPhone: Text("Moving to a new iPhone", bundle: .module)
        }
    }

    var paragraphs: [Text] {
        switch self {
        case .surprises: [
            Text("This is the heart of MimoDays. At a random time within your hours, a notification comes. Drop what you're doing and, wherever you are, capture what's around you right away, just as it is: a real piece of an ordinary day, not a perfect shot.", bundle: .module, comment: "Help › Surprises: the app's main idea"),
            Text("Tap the notification and the camera opens at once. A surprise stays open for a while, 15 minutes unless you change it; what you capture in that time is marked Surprise.", bundle: .module, comment: "Help › Surprises: what a tap on the notification does; Surprise is the label on such moments"),
            Text("Missed one? Nothing happens. There are no streaks or scores.", bundle: .module),
            Text("Choose how often, on which days, between which hours and how long a surprise stays open in Settings › Surprises. You can pause them for the rest of today, for a week or until you resume them.", bundle: .module),
        ]
        case .selfieWindow: [
            Text("On iPhones that can use both cameras at once, MimoDays captures what's in front of you and your face in a small window, in the same photo or video.", bundle: .module),
            Text("Drag the window to any corner. Touch and hold it to change its corner and size. MimoDays remembers where you leave it; Settings › Camera sets it too.", bundle: .module),
            Text("On other iPhones, MimoDays uses one camera.", bundle: .module),
        ]
        case .permissions: [
            Text("Camera and microphone: for photos, videos and voice notes.", bundle: .module),
            Text("Location, if you allow it: to save where a moment happened and to show where you are on the map.", bundle: .module),
            Text("Notifications, if you allow them: for surprises, and to tell you when a movie is ready or a backup is due.", bundle: .module),
            Text("Photos: only to save what you export. Importing uses the system picker and needs no access.", bundle: .module),
            Text("Face ID, if you turn on App Lock.", bundle: .module),
            Text("You can change any of them in iOS Settings.", bundle: .module),
        ]
        case .newIPhone: [
            Text("On this iPhone, open Settings › Backup and make a backup. Save it to iCloud Drive, another place in Files, or a computer.", bundle: .module),
            Text("On the new iPhone, install MimoDays and, after the introduction, open Settings › Backup, tap Restore from a backup and choose that file.", bundle: .module),
            Text("Your moments come back with their notes, voice notes, places, collections and movie projects. Settings aren't included; set them again.", bundle: .module),
        ]
        }
    }
}

/// S07: the app, its version, how it works, and Rate and the privacy statement.
struct HelpView: View {
    var version = HelpView.appVersion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @Environment(\.replayOnboarding) private var replayOnboarding
    @State private var composesMail = false
    @State private var showsAddress = false

    /// "1.0 (12)".
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Settings", bundle: .module), title: Text("Help & about", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        AppIconMark()
                        Text(verbatim: "MimoDays")
                            .textStyle(TextStyle(.fraunces, size: 24, weight: 600, relativeTo: .title2, maximumScale: 1.35))
                            .foregroundStyle(ColorToken.textPrimary.color)
                            .padding(.top, 12)
                        Text("Version \(version)", bundle: .module, comment: "Help & about (S07): the app's version and build, e.g. 'Version 1.0 (12)'")
                            .textStyle(TextStyle(.nunito, size: 13.5, weight: 600, relativeTo: .footnote))
                            .foregroundStyle(ColorToken.textSecondary.color)
                    }
                    .frame(maxWidth: .infinity)
                    Text("How it works", bundle: .module)
                        .textStyle(.labelCaps)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                    DataCard {
                        ForEach(HelpArticle.allCases, id: \.self) { article in
                            if article != HelpArticle.allCases.first { DataSeparator() }
                            NavigationLink(value: SettingsRoute.helpArticle(article)) {
                                SettingsValueRow(title: article.title, value: Text(verbatim: ""))
                            }
                            .accessibilityIdentifier("help.\(article.rawValue)")
                        }
                        DataSeparator()
                        Button(action: replayOnboarding) {
                            SettingsValueRow(
                                title: Text("Show the introduction again", bundle: .module, comment: "Help & about (S07): opens onboarding again from its first page"),
                                value: Text(verbatim: "")
                            )
                        }
                        .accessibilityIdentifier("help.introduction")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    DataCard {
                        if let feedback = AppLinks.feedback {
                            Button { sendFeedback(feedback) } label: {
                                DataIconRow(icon: .glyphNote, title: Text("Send feedback", bundle: .module))
                            }
                            .accessibilityIdentifier("help.feedback")
                            DataSeparator(leading: 64)
                        }
                        Button { requestReview() } label: {
                            DataIconRow(icon: .glyphStar, title: Text("Rate MimoDays", bundle: .module))
                        }
                        .accessibilityIdentifier("help.rate")
                        DataSeparator(leading: 64)
                        NavigationLink(value: SettingsRoute.dataUse(back: .help)) {
                            DataIconRow(icon: .glyphLock, title: Text("Privacy statement", bundle: .module))
                        }
                        .accessibilityIdentifier("help.privacy")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .sheet(isPresented: $composesMail) {
            MailComposer(to: AppLinks.feedbackAddress, subject: "MimoDays \(version)") { composesMail = false }
                .ignoresSafeArea()
        }
        .alert(Text("Send feedback", bundle: .module), isPresented: $showsAddress) {
            Button { UIPasteboard.general.string = AppLinks.feedbackAddress } label: {
                Text("Copy address", bundle: .module, comment: "Help › Send feedback, when no mail app can open: copies the feedback email address")
            }
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: {
            Text("No mail app is set up on this device. Write to \(AppLinks.feedbackAddress) from any app.", bundle: .module, comment: "Help › Send feedback, when no mail app can open; the argument is the email address")
        }
    }

    /// Mail in place when an account is set up; otherwise the person's own mail app; otherwise the address to copy.
    /// A `mailto:` link alone does nothing visible when no app takes it.
    private func sendFeedback(_ url: URL) {
        if MFMailComposeViewController.canSendMail() {
            composesMail = true
        } else {
            openURL(url) { accepted in
                if !accepted { showsAddress = true }
            }
        }
    }
}

/// The system's mail sheet, addressed and with a subject.
private struct MailComposer: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients([to])
        controller.setSubject(subject)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish()
        }
    }
}

/// `Brand / App icon`: the coral squircle with the cream wordmark.
private struct AppIconMark: View {
    var body: some View {
        ZStack {
            Icon.brandWordmark.image.resizable()
            Icon.brandWordmarkStar.image.resizable()
        }
        .foregroundStyle(Color(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEF / 255))
        .frame(width: 64, height: 64 * 33 / 103.7)
        .frame(width: 84, height: 84)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0xF2 / 255, green: 0x76 / 255, blue: 0x50 / 255), Color(red: 0xE2 / 255, green: 0x58 / 255, blue: 0x2F / 255)],
                    startPoint: .top, endPoint: .bottom
                ))
                .shadow(color: Color(red: 0x4B / 255, green: 0x29 / 255, blue: 0x38 / 255).opacity(0.2), radius: 6, y: 4)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// One "How it works" page.
struct HelpArticleView: View {
    let article: HelpArticle
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Help & about", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    article.title
                        .textStyle(.displaySheet)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        paragraph.textStyle(.body)
                            .foregroundStyle(ColorToken.textBody.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if article == .permissions {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Text("Open iOS Settings", bundle: .module)
                        }
                        .buttonStyle(.text)
                        .accessibilityIdentifier("help.openSettings")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }
}

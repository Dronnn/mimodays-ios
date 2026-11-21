import DesignSystem
import MessageUI
import SwiftUI
import UIKit

enum AppLinks {
    /// S07 "Send feedback": the same address as the site's Support page and the App Store listing.
    static let feedbackAddress = "mimodays@mrmaier.com"
    static let feedback = URL(string: "mailto:\(feedbackAddress)")
    /// S07 "Rate MimoDays": the App Store's review page (the system's rating prompt may not show when asked).
    static let review = URL(string: "https://apps.apple.com/app/id6835025354?action=write-review")
}

/// S07 "How it works": one short page each.
enum HelpArticle: String, CaseIterable, Hashable {
    case surprises
    case selfieWindow
    case permissions
    case newIPhone
    case cameraShortcut
    case hideFromMemories
    case remindLater
    case tagsAndMood
    case momentsFromPhotos
    case thenNow
    case oneSecond
    case writeMoment
    case fallbackReminder

    var title: Text {
        switch self {
        case .surprises: Text("Surprises", bundle: .module)
        case .selfieWindow: Text("The selfie window", bundle: .module)
        case .permissions: Text("Permissions", bundle: .module)
        case .newIPhone: Text("Moving to a new iPhone", bundle: .module)
        case .cameraShortcut: Text("Open the camera quickly", bundle: .module)
        case .hideFromMemories: Text("Hide from memories", bundle: .module)
        case .remindLater: Text("Remind me later", bundle: .module)
        case .tagsAndMood: Text("Tags and mood", bundle: .module)
        case .momentsFromPhotos: Text("Moments from Photos", bundle: .module)
        case .thenNow: Text("Then & Now", bundle: .module)
        case .oneSecond: Text("One second per day", bundle: .module)
        case .writeMoment: Text("Write a moment", bundle: .module)
        case .fallbackReminder: Text("Fallback reminder", bundle: .module)
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
            Text("Photos: to save what you export and, if you allow it, to find moments from a day you choose. Importing through the system picker needs no access.", bundle: .module),
            Text("Face ID, if you turn on App Lock.", bundle: .module),
            Text("You can change any of them in iOS Settings.", bundle: .module),
        ]
        case .newIPhone: [
            Text("On this iPhone, open Settings › Backup and make a backup. Save it to iCloud Drive, another place in Files, or a computer.", bundle: .module),
            Text("On the new iPhone, install MimoDays and, after the introduction, open Settings › Backup, tap Restore from a backup and choose that file.", bundle: .module),
            Text("Your moments come back with their notes, voice notes, places, collections and movie projects. Settings aren't included; set them again.", bundle: .module),
        ]
        // P8.1: the steps as iOS names them.
        case .cameraShortcut: [
            Text("Add MimoDays Camera once, then open the camera with one press, without looking for the app.", bundle: .module),
            Text("Shortcuts & Siri: say “Open MimoDays Camera”, or add it in the Shortcuts app.", bundle: .module),
            Text("Control Center: swipe down from the top right, tap +, Add a Control, MimoDays Camera.", bundle: .module),
            Text("Lock Screen: touch and hold the Lock Screen, tap Customize, Lock Screen, tap a button at the bottom, then MimoDays Camera.", bundle: .module),
            Text("Action button (iPhone 15 Pro and later): Settings › Action Button › Shortcut › Open MimoDays Camera.", bundle: .module),
            Text("If the iPhone or App Lock is locked, Face ID comes first.", bundle: .module),
        ]
        // P8.3, P8.7 (P8.15): the names as the menus show them.
        case .hideFromMemories: [
            Text("Open a moment, tap •••, then Hide from memories.", bundle: .module),
            Text("To hide a whole day, open the day, tap •••, then Hide this day from memories.", bundle: .module),
            Text("Hidden moments stay in your archive, Search and Map. They just don't come back in On this day or automatic movies.", bundle: .module),
            Text("To show them again, use the same menu.", bundle: .module),
        ]
        case .remindLater: [
            Text("When a surprise arrives at a bad time, touch and hold its notification, then tap Remind me later.", bundle: .module),
            Text("The same surprise comes back once, later today, inside your surprise hours.", bundle: .module),
        ]
        // P8.15: the rest of 1.0.7, the names as the screens show them.
        case .tagsAndMood: [
            Text("When you save or edit a moment, tap Tags to add words to search for later, up to 10, and Mood to pick how it felt.", bundle: .module),
            Text("In Search, tap Filters, then Tags or Mood, to narrow the results.", bundle: .module),
            Text("Only you set the mood. MimoDays never guesses it.", bundle: .module),
        ]
        case .momentsFromPhotos: [
            Text("On a day with no moments, Today and the calendar show Find moments in Photos. Pick photos and videos taken that day, tap Review, then Import.", bundle: .module),
            Text("MimoDays looks only at that date, and only after you allow Photos access. Browse Photos opens the system picker for any date, with no access needed.", bundle: .module),
            Text("Live Photos keep their motion: on the card, tap Play Live Photo.", bundle: .module),
        ]
        case .thenNow: [
            Text("Open an old moment, tap •••, then Capture this again, and take the same picture today.", bundle: .module),
            Text("On the back of the card, Then & Now shows both side by side. With several repeats, choose the one to compare.", bundle: .module),
        ]
        case .oneSecond: [
            Text("In Movies, tap New movie, then One second per day, and pick a month or a year.", bundle: .module),
            Text("Each day with moments gives one second: its first surprise, or else its earliest moment. Tap Change on a day to pick another.", bundle: .module),
        ]
        case .writeMoment: [
            Text("On Today, tap Add a moment, then Write a moment.", bundle: .module),
            Text("Write what you want to remember, and add a place, tags and mood if you like. It becomes a paper card among your photos and videos.", bundle: .module),
        ]
        case .fallbackReminder: [
            Text("In Settings › Surprises, turn on Fallback reminder and choose a time.", bundle: .module),
            Text("On days with no surprise planned, MimoDays reminds you at that time. It stays off unless you turn it on.", bundle: .module),
        ]
        }
    }
}

/// S07: the app, its version, how it works, and Rate and the privacy statement.
struct HelpView: View {
    var version = HelpView.appVersion
    @Environment(\.dismiss) private var dismiss
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
                            .textStyle(TextStyle(.heading, size: 24, weight: 600, relativeTo: .title2, maximumScale: 1.35))
                            .foregroundStyle(ColorToken.textPrimary.color)
                            .padding(.top, 12)
                        Text("Version \(version)", bundle: .module, comment: "Help & about (S07): the app's version and build, e.g. 'Version 1.0 (12)'")
                            .textStyle(TextStyle(.body, size: 13.5, weight: 600, relativeTo: .footnote))
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
                        Button { if let review = AppLinks.review { openURL(review) } } label: {
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

import Core
import DesignSystem
import SwiftUI

/// The places Settings opens for the archive's data (E06, E09 and what they lead to).
enum DataRoute: Hashable {
    case storage
    /// E06, from Settings, Storage or Delete all data's Back up first.
    case backup(back: SettingsBack)
    case recentlyDeleted
}

struct StorageScreen: View {
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library { ModelHost({ StorageModel(library: library) }) { StorageHost(model: $0) } }
    }
}

private struct StorageHost: View {
    @State var model: StorageModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        StorageView(model: model) {
            router.isSettingsPresented = false
            router.selectedTab = .movies
        }
        .onAppear { model.load() }
    }
}

/// E09: how much MimoDays uses, as a bar and by kind; temporary files can go, originals never.
struct StorageView: View {
    let model: StorageModel
    /// Rendered movies open the Movies tab.
    let openMovies: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Settings", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Storage", bundle: .module)
                        .textStyle(.pageTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    Text("\(Self.bytes(model.usage.total)) used by MimoDays", bundle: .module)
                        .textStyle(.rowTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .padding(.horizontal, 20)
                        .padding(.top, 15)
                    StorageBar(parts: parts.map { ($0.color, $0.bytes) })
                        .padding(.horizontal, 16)
                        .padding(.top, 9)
                    DataCard {
                        ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                            if index > 0 { DataSeparator() }
                            if part.opens {
                                Button(action: openMovies) { row(part) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier(part.id)
                            } else {
                                row(part).accessibilityIdentifier(part.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 17)
                    Button { model.clearTemporary() } label: { Text("Clear temporary files", bundle: .module) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.usage.temporary == 0)
                        .accessibilityIdentifier("storage.clear")
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    DataCard {
                        NavigationLink(value: DataRoute.recentlyDeleted) {
                            DataIconRow(
                                icon: .glyphTrash, title: Text("Recently deleted", bundle: .module),
                                value: Text("\(model.deletedCount) · \(Self.bytes(model.deletedBytes))", bundle: .module)
                            )
                        }
                        .accessibilityIdentifier("storage.recentlyDeleted")
                        DataSeparator(leading: 64)
                        NavigationLink(value: DataRoute.backup(back: .storage)) {
                            DataIconRow(icon: .glyphArchive, title: Text("Backup", bundle: .module), value: lastBackup)
                        }
                        .accessibilityIdentifier("storage.backup")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private struct Part {
        let id: String
        let color: Color
        let title: Text
        let detail: Text?
        let bytes: Int64
        var opens = false
    }

    private var parts: [Part] {
        [
            Part(
                id: "storage.moments", color: ColorToken.actionCoral.color, title: Text("Moments", bundle: .module),
                detail: Text("photos, videos, selfie windows", bundle: .module), bytes: model.usage.moments
            ),
            Part(
                id: "storage.movies", color: Color(hex: 0xF2A93B), title: Text("Rendered movies", bundle: .module),
                detail: Text("can be made again", bundle: .module), bytes: model.usage.movies, opens: true
            ),
            Part(id: "storage.voice", color: Color(hex: 0xA9B88F), title: Text("Voice notes", bundle: .module), detail: nil, bytes: model.usage.voiceNotes),
            Part(
                id: "storage.temporary", color: Color(hex: 0xB5A69A), title: Text("Temporary files", bundle: .module),
                detail: Text("previews and thumbnails", bundle: .module), bytes: model.usage.temporary
            ),
        ]
    }

    private func row(_ part: Part) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle().fill(part.color).frame(width: 10, height: 10)
                .frame(maxHeight: .infinity, alignment: part.detail == nil ? .center : .top)
                .padding(.top, part.detail == nil ? 0 : 6)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityHidden(true)
            DataRowLabel(title: part.title, detail: part.detail)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text(Self.bytes(part.bytes)).textStyle(.rowValue).foregroundStyle(ColorToken.textTertiary.color)
                if part.opens { DataChevron() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var lastBackup: Text {
        guard let date = model.lastBackup else { return Text("Never", bundle: .module) }
        return Text(DataFormat.ago(date, now: .now))
    }

    static func bytes(_ count: Int64) -> String { count.formatted(.byteCount(style: .file, spellsOutZero: false).locale(AppLanguage.shared.locale)) }
}

/// `Storage / Bar`: one 14 pt bar split by kind with 2 pt gaps; a kind too small to see still shows 6 pt.
struct StorageBar: View {
    let parts: [(Color, Int64)]

    var body: some View {
        GeometryReader { proxy in
            let shown = parts.filter { $0.1 > 0 }
            let total = Double(shown.reduce(Int64(0)) { $0 + $1.1 })
            let gaps = CGFloat(max(shown.count - 1, 0)) * 2
            let small = shown.filter { total > 0 && Double($0.1) / total * (proxy.size.width - gaps) < 6 }.count
            let room = proxy.size.width - gaps - CGFloat(small) * 6
            let large = Double(shown.filter { Double($0.1) / max(total, 1) * (proxy.size.width - gaps) >= 6 }.reduce(Int64(0)) { $0 + $1.1 })
            HStack(spacing: 2) {
                if shown.isEmpty {
                    ColorToken.surfaceChip.color
                } else {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, part in
                        let width = Double(part.1) / total * (proxy.size.width - gaps) < 6 ? 6 : room * Double(part.1) / max(large, 1)
                        part.0.frame(width: width)
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

import Core
import SwiftUI
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif

extension View {
    /// P8.12 DD03: Apple's Journaling Suggestions picker, or the UI tests' stand-in where it can't run. `picked` gets
    /// a way to open the suggestion chosen; closing the picker without one does nothing.
    func journalingPicker(
        isPresented: Binding<Bool>, fixture: LaunchConfiguration.JournalingFixture?,
        picked: @escaping @MainActor (@escaping @MainActor () async throws -> JournalingPick) -> Void
    ) -> some View {
        modifier(JournalingPickerModifier(isPresented: isPresented, fixture: fixture, picked: picked))
    }
}

private struct JournalingPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let fixture: LaunchConfiguration.JournalingFixture?
    let picked: @MainActor (@escaping @MainActor () async throws -> JournalingPick) -> Void

    func body(content: Content) -> some View {
        if let fixture {
            content.onChange(of: isPresented) { _, shown in
                guard shown else { return }
                isPresented = false
                picked { try fixture.pick() }
            }
        } else {
            #if canImport(JournalingSuggestions)
            content.journalingSuggestionsPicker(isPresented: $isPresented) { @Sendable [picked] suggestion in
                // Only this one suggestion reaches the app; its photos and prompts are all MimoDays reads.
                let pick = await JournalingPick(suggestion)
                await picked { pick }
            }
            #else
            content
            #endif
        }
    }
}

#if canImport(JournalingSuggestions)
extension JournalingPick {
    init(_ suggestion: JournalingSuggestion) async {
        let photos = await suggestion.content(forType: JournalingSuggestion.Photo.self).map { Photo(url: $0.photo, date: $0.date) }
        let prompts = await suggestion.content(forType: JournalingSuggestion.Reflection.self).map(\.prompt)
        self.init(title: suggestion.title, date: suggestion.date?.start, photos: photos, prompts: prompts)
    }
}
#endif

import Persistence
import SwiftData

public enum TestStore {
    /// An in-memory container whose main context doesn't autosave. The autosave timer can fire after a test has ended and
    /// its container is gone, which traps in SwiftData (CI, 2026-11-15). The code under test saves explicitly.
    @MainActor public static func container() throws -> ModelContainer {
        let container = try MimoDaysStore.makeContainer(inMemory: true)
        container.mainContext.autosaveEnabled = false
        return container
    }
}

import Foundation
import Persistence
import SwiftData

extension ModelContext {
    /// The thumbnail each of these moments shows now, in one read: a grid that decoded one from another file (the
    /// viewer moved the window or chose halves since) reads it again.
    func thumbnailPaths(of ids: [UUID]) -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let moments = (try? fetch(FetchDescriptor<Moment>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        var paths: [UUID: String] = [:]
        for moment in moments {
            paths[moment.id] = moment.media.first(where: { $0.role == .thumbnail })?.relativePath
        }
        return paths
    }
}

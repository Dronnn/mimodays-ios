import Foundation
import Persistence
import SwiftData

/// An imported photo or video keeps its own shape (Andrew, 2026-11-20), as if the camera had taken it in that format:
/// wide ones 16:9, square ones 1:1, the rest 9:16.
extension CaptureFormat {
    static func fitting(width: Int, height: Int, orientation: Int = 1) -> CaptureFormat {
        guard width > 0, height > 0 else { return .portrait }
        // EXIF 5...8: the picture is stored turned a quarter.
        let turned = (5 ... 8).contains(orientation)
        let ratio = Double(turned ? height : width) / Double(turned ? width : height)
        if ratio > 1.1 { return .landscape }
        if ratio >= 0.9 { return .square }
        return .portrait
    }
}

extension Moment {
    /// Imports take the shape of their picture; anything else keeps the format it was taken in.
    func fitImportedFormat() {
        guard origin == .imported, let main = media.first(where: { $0.role == .rearSource || $0.role == .frontSource }) else { return }
        captureFormat = .fitting(width: main.pixelWidth, height: main.pixelHeight, orientation: main.orientation)
    }
}

enum ImportedFormats {
    private static let repairedKey = "importedFormatsRepaired"

    /// Imports from before 2026-11-20 were all kept 9:16: once, each gets the shape of its picture.
    static func repairOnce(context: ModelContext, defaults: UserDefaults) {
        guard !defaults.bool(forKey: repairedKey) else { return }
        let imported = MomentOrigin.imported.rawValue
        let moments = (try? context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.originRaw == imported }))) ?? []
        moments.forEach { $0.fitImportedFormat() }
        guard (try? context.save()) != nil else { return }
        defaults.set(true, forKey: repairedKey)
    }
}

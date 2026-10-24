import AppKit
import SwiftUI

struct Place: Identifiable, Hashable {
    let name: String
    let symbol: String
    let color: Color
    let url: URL
    var id: String { url.path }
}

struct Volume: Identifiable, Hashable {
    let url: URL
    let name: String
    let total: Int64
    let free: Int64
    let isInternal: Bool
    let isEjectable: Bool
    var id: String { url.path }
    var usedFraction: Double { total > 0 ? Double(total - free) / Double(total) : 0 }
}

enum Places {
    static let thisMacTag = "::this-mac"

    static var quickAccess: [Place] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var places = [
            Place(name: "Home", symbol: "house.fill", color: .orange, url: home),
            Place(name: "Desktop", symbol: "menubar.dock.rectangle", color: .teal, url: home.appendingPathComponent("Desktop")),
            Place(name: "Downloads", symbol: "arrow.down.circle.fill", color: .green, url: home.appendingPathComponent("Downloads")),
            Place(name: "Documents", symbol: "doc.fill", color: .blue, url: home.appendingPathComponent("Documents")),
            Place(name: "Pictures", symbol: "photo.fill", color: .pink, url: home.appendingPathComponent("Pictures")),
            Place(name: "Music", symbol: "music.note", color: .red, url: home.appendingPathComponent("Music")),
            Place(name: "Movies", symbol: "film.fill", color: .purple, url: home.appendingPathComponent("Movies")),
            Place(name: "Applications", symbol: "square.grid.2x2.fill", color: .indigo, url: URL(fileURLWithPath: "/Applications")),
        ]
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: iCloud.path) {
            places.insert(Place(name: "iCloud Drive", symbol: "icloud.fill", color: .cyan, url: iCloud), at: 1)
        }
        return places
    }

    static func volumes() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            return Volume(
                url: url,
                name: v.volumeLocalizedName ?? url.lastPathComponent,
                total: Int64(v.volumeTotalCapacity ?? 0),
                free: free,
                isInternal: v.volumeIsInternal ?? false,
                isEjectable: (v.volumeIsEjectable ?? false) || (v.volumeIsRemovable ?? false)
            )
        }
    }
}

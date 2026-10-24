import AppKit
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey,
    ]

    let url: URL
    let name: String
    let isFolder: Bool
    let isHidden: Bool
    let size: Int64
    let modified: Date
    let typeName: String

    var id: String { url.path }
    /// Folders sort below every file when sorting by size, like Explorer.
    var sortSize: Int64 { isFolder ? -1 : size }
    var sizeText: String { isFolder ? "" : Self.sizeFormatter.string(fromByteCount: size) }

    static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
        var isDir = values?.isDirectory ?? false
        var isPackage = values?.isPackage ?? false
        if values?.isSymbolicLink == true {
            let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            isDir = target?.isDirectory ?? false
            isPackage = target?.isPackage ?? false
        }
        self.url = url
        name = url.lastPathComponent
        isFolder = isDir && !isPackage
        isHidden = values?.isHidden ?? false
        size = Int64(values?.fileSize ?? 0)
        modified = values?.contentModificationDate ?? .distantPast
        typeName = isFolder ? "File folder" : (values?.localizedTypeDescription ?? "File")
    }

    static func contents(of dir: URL, showHidden: Bool) throws -> [FileItem] {
        try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: resourceKeys,
            options: showHidden ? [] : [.skipsHiddenFiles]
        ).map(FileItem.init)
    }

    /// Recursive name search below `root`. Runs off the main actor and stops when the task is cancelled.
    static func search(in root: URL, matching query: String, showHidden: Bool, limit: Int = 5000) async -> [FileItem] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: resourceKeys, options: options, errorHandler: { _, _ in true }
        ) else { return [] }
        var results: [FileItem] = []
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled || results.count >= limit { break }
            if url.lastPathComponent.localizedCaseInsensitiveContains(query) {
                results.append(FileItem(url: url))
            }
        }
        return results
    }

    /// Picks a free name in `dir`: "New folder (2)" style, or "name - Copy (2).ext" when `copySuffix` is set.
    static func uniqueURL(in dir: URL, name: String, copySuffix: Bool = false) -> URL {
        let fm = FileManager.default
        let first = dir.appendingPathComponent(name)
        if !copySuffix, !fm.fileExists(atPath: first.path) { return first }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        let base = copySuffix ? "\(stem) - Copy" : stem
        var n = copySuffix ? 1 : 2
        while true {
            let label = n > 1 ? "\(base) (\(n))" : base
            let candidate = dir.appendingPathComponent(ext.isEmpty ? label : "\(label).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    enum TransferMode { case copy, move, auto }

    /// Copies or moves `sources` into `dir`. `.auto` moves within a volume and copies across volumes.
    /// Returns error messages for the items that failed.
    static func transfer(_ sources: [URL], to dir: URL, mode: TransferMode) async -> [String] {
        let fm = FileManager.default
        var errors: [String] = []
        let destVolume = volumeID(of: dir)
        for src in sources {
            let move: Bool
            switch mode {
            case .copy: move = false
            case .move: move = true
            case .auto: move = destVolume != nil && volumeID(of: src) == destVolume
            }
            if move && src.deletingLastPathComponent().path == dir.path { continue }
            if dir.path == src.path || dir.path.hasPrefix(src.path + "/") {
                errors.append("You can't put \"\(src.lastPathComponent)\" inside itself.")
                continue
            }
            let collides = fm.fileExists(atPath: dir.appendingPathComponent(src.lastPathComponent).path)
            let dest = collides
                ? uniqueURL(in: dir, name: src.lastPathComponent, copySuffix: true)
                : dir.appendingPathComponent(src.lastPathComponent)
            do {
                if move { try fm.moveItem(at: src, to: dest) } else { try fm.copyItem(at: src, to: dest) }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return errors
    }

    private static func volumeID(of url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }

    static func zip(_ names: [String], in dir: URL, to dest: URL) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        // "./" keeps a file named like "-T" from being read as a zip option.
        process.arguments = ["-r", "-y", "-q", dest.path] + names.map { "./" + $0 } + ["-x", "*.DS_Store"]
        process.currentDirectoryURL = dir
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func folderSize(_ url: URL) async -> (bytes: Int64, files: Int, folders: Int) {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [], errorHandler: { _, _ in true }
        ) else { return (0, 0, 0) }
        var bytes: Int64 = 0, files = 0, folders = 0
        while let child = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { folders += 1 } else { files += 1; bytes += Int64(values?.fileSize ?? 0) }
        }
        return (bytes, files, folders)
    }
}

final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for url: URL, size: CGFloat = 16) -> NSImage {
        let key = "\(url.path)#\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path).copy() as! NSImage
        image.size = NSSize(width: size, height: size)
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Watches a single directory and calls back on the main queue when its contents change.
final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link], queue: .main
        )
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { source.cancel() }
}

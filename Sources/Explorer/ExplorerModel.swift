import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ViewMode: String { case details, icons }

enum SortKey: String, CaseIterable, Identifiable {
    case name, modified, type, size
    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .modified: "Date modified"
        case .type: "Type"
        case .size: "Size"
        }
    }

    var keyPath: PartialKeyPath<FileItem> {
        switch self {
        case .name: \FileItem.name
        case .modified: \FileItem.modified
        case .type: \FileItem.typeName
        case .size: \FileItem.sortSize
        }
    }

    func comparator(_ order: SortOrder) -> KeyPathComparator<FileItem> {
        switch self {
        case .name: KeyPathComparator(\FileItem.name, comparator: .localizedStandard, order: order)
        case .modified: KeyPathComparator(\FileItem.modified, order: order)
        case .type: KeyPathComparator(\FileItem.typeName, comparator: .localizedStandard, order: order)
        case .size: KeyPathComparator(\FileItem.sortSize, order: order)
        }
    }
}

/// State for one Explorer window: where it is, what it shows, and the file operations it can run.
@MainActor
final class ExplorerModel: ObservableObject {
    /// `nil` means the "This Mac" overview page.
    @Published private(set) var location: URL?
    @Published private(set) var items: [FileItem] = []
    @Published var selection = Set<String>()
    @Published var sortOrder = [SortKey.name.comparator(.forward)] { didSet { applySort() } }
    @Published var searchText = "" { didSet { if searchText != oldValue && !suppressSearch { scheduleSearch() } } }
    @Published var showHidden = false { didSet { reload() } }
    @Published var showExtensions = true
    @Published var viewMode: ViewMode = .details
    @Published private(set) var isSearching = false
    @Published private(set) var busy = false
    @Published private(set) var loadError: String?
    @Published var alertMessage: String?
    @Published var renameTarget: FileItem?
    @Published var renameText = ""
    @Published var propertiesTarget: FileItem?
    @Published var addressFocusRequest = 0
    @Published var searchFocusRequest = 0

    weak var window: NSWindow?

    private var baseItems: [FileItem] = []
    private var backStack: [URL?] = []
    private var forwardStack: [URL?] = []
    private var watcher: DirectoryWatcher?
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var suppressSearch = false
    private var selectionAnchor: String?

    init(start: URL? = FileManager.default.homeDirectoryForCurrentUser) {
        navigate(to: start, recordHistory: false)
        KeyRouter.shared.register(self)
    }

    // MARK: - Derived state

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { location != nil }
    var activeQuery: String { searchText.trimmingCharacters(in: .whitespaces) }
    var title: String { location.map { FileManager.default.displayName(atPath: $0.path) } ?? "This Mac" }
    var selectedItems: [FileItem] { items.filter { selection.contains($0.id) } }

    func targets(for ids: Set<String>) -> [FileItem] { items.filter { ids.contains($0.id) } }

    func displayName(_ item: FileItem) -> String {
        guard !showExtensions, !item.isFolder else { return item.name }
        let stem = (item.name as NSString).deletingPathExtension
        return stem.isEmpty ? item.name : stem
    }

    var sortKey: SortKey {
        get { SortKey.allCases.first { $0.keyPath == sortOrder.first?.keyPath } ?? .name }
        set { sortOrder = [newValue.comparator(sortAscending ? .forward : .reverse)] }
    }

    var sortAscending: Bool {
        get { sortOrder.first?.order != .reverse }
        set { sortOrder = [sortKey.comparator(newValue ? .forward : .reverse)] }
    }

    // MARK: - Navigation

    func navigate(to url: URL?, recordHistory: Bool = true) {
        let target = url?.standardizedFileURL
        if recordHistory {
            guard target?.path != location?.path else { return }
            backStack.append(location)
            forwardStack.removeAll()
        }
        location = target
        searchTask?.cancel()
        isSearching = false
        suppressSearch = true
        searchText = ""
        suppressSearch = false
        selection = []
        selectionAnchor = nil
        watcher = target.flatMap { DirectoryWatcher(url: $0) { [weak self] in self?.directoryChanged() } }
        reload()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(location)
        navigate(to: previous, recordHistory: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(location)
        navigate(to: next, recordHistory: false)
    }

    func goUp() {
        guard let current = location else { return }
        navigate(to: current.path == "/" ? nil : current.deletingLastPathComponent())
        // Like Explorer, highlight the folder we just came out of.
        if items.contains(where: { $0.id == current.path }) { selection = [current.path] }
    }

    /// Handles a path typed into the address bar.
    func go(toPath raw: String) {
        let path = (raw as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            let url = URL(fileURLWithPath: path)
            if isDir.boolValue && !NSWorkspace.shared.isFilePackage(atPath: path) {
                navigate(to: url)
            } else {
                NSWorkspace.shared.open(url)
            }
        } else {
            alertMessage = "Explorer can't find '\(raw)'. Check the spelling and try again."
        }
    }

    func open(_ item: FileItem) {
        if item.isFolder { navigate(to: item.url) } else { NSWorkspace.shared.open(item.url) }
    }

    func open(ids: Set<String>) {
        let list = targets(for: ids)
        if list.count == 1 {
            open(list[0])
        } else {
            list.filter { !$0.isFolder }.forEach { NSWorkspace.shared.open($0.url) }
        }
    }

    func openSelection() { open(ids: selection) }

    func open(_ url: URL, with app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Loading

    func reload() {
        if !activeQuery.isEmpty { scheduleSearch(); return }
        guard let url = location else {
            baseItems = []
            loadError = nil
            applySort()
            return
        }
        do {
            baseItems = try FileItem.contents(of: url, showHidden: showHidden)
            loadError = nil
        } catch {
            baseItems = []
            loadError = error.localizedDescription
        }
        applySort()
    }

    private func directoryChanged() {
        guard activeQuery.isEmpty else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    private func applySort() {
        let order = sortOrder
        items = baseItems.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            for comparator in order {
                switch comparator.compare(a, b) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
        let ids = Set(items.map(\.id))
        if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard let root = location else { return }
        let query = activeQuery
        guard !query.isEmpty else {
            isSearching = false
            reload()
            return
        }
        isSearching = true
        let hidden = showHidden
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let results = await FileItem.search(in: root, matching: query, showHidden: hidden)
            guard !Task.isCancelled, let self else { return }
            self.baseItems = results
            self.loadError = nil
            self.isSearching = false
            self.applySort()
        }
    }

    // MARK: - Selection

    func selectAll() { selection = Set(items.map(\.id)) }
    func selectNone() { selection = [] }
    func invertSelection() { selection = Set(items.map(\.id)).subtracting(selection) }

    /// Click handling for the icon grid (the details table manages its own selection).
    func click(_ item: FileItem) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            selectionAnchor = item.id
        } else if mods.contains(.shift), let anchor = selectionAnchor,
                  let a = items.firstIndex(where: { $0.id == anchor }),
                  let b = items.firstIndex(where: { $0.id == item.id }) {
            selection = Set(items[min(a, b)...max(a, b)].map(\.id))
        } else {
            selection = [item.id]
            selectionAnchor = item.id
        }
    }

    // MARK: - File operations

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { alertMessage = error.localizedDescription }
    }

    func newFolder() {
        guard let dir = location else { return }
        let url = FileItem.uniqueURL(in: dir, name: "New folder")
        perform { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        revealAndRename(url)
    }

    func newTextFile() {
        guard let dir = location else { return }
        let url = FileItem.uniqueURL(in: dir, name: "New Text Document.txt")
        if !FileManager.default.createFile(atPath: url.path, contents: Data()) {
            alertMessage = "Couldn't create a file in \(title)."
            return
        }
        revealAndRename(url)
    }

    private func revealAndRename(_ url: URL) {
        reload()
        guard let item = items.first(where: { $0.id == url.path }) else { return }
        selection = [item.id]
        startRename(item)
    }

    func startRename(_ item: FileItem) {
        renameText = item.name
        renameTarget = item
    }

    func renameSelection() {
        if let item = selectedItems.first, selection.count == 1 { startRename(item) }
    }

    func commitRename() {
        guard let item = renameTarget else { return }
        renameTarget = nil
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != item.name else { return }
        if newName.contains("/") || newName.contains(":") {
            alertMessage = "A file name can't contain \"/\" or \":\"."
            return
        }
        let dest = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        perform {
            let fm = FileManager.default
            if newName.lowercased() == item.name.lowercased() {
                // Case-only rename on a case-insensitive volume needs a hop through a temporary name.
                let temp = item.url.deletingLastPathComponent().appendingPathComponent(".rename-\(UUID().uuidString)")
                try fm.moveItem(at: item.url, to: temp)
                try fm.moveItem(at: temp, to: dest)
            } else {
                try fm.moveItem(at: item.url, to: dest)
            }
        }
        reload()
        selection = [dest.path]
    }

    func trash(ids: Set<String>) {
        let list = targets(for: ids)
        guard !list.isEmpty else { return }
        for item in list {
            perform { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
        }
        reload()
    }

    func copy(ids: Set<String>, cut: Bool) {
        let urls = targets(for: ids).map(\.url)
        guard !urls.isEmpty else { return }
        FileClipboard.shared.set(urls, cut: cut)
    }

    func copyPaths(ids: Set<String>) {
        let paths = targets(for: ids).map(\.url.path)
        let text = paths.isEmpty ? (location?.path ?? "") : paths.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func paste() {
        guard let dest = location else { return }
        let (urls, isCut) = FileClipboard.shared.contents()
        guard !urls.isEmpty else { return }
        runTransfer(urls, to: dest, mode: isCut ? .move : .copy)
        if isCut { FileClipboard.shared.clearCut() }
    }

    func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let dest = location else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty { runTransfer(urls, to: dest, mode: .auto) }
        }
        return true
    }

    private func runTransfer(_ urls: [URL], to dest: URL, mode: FileItem.TransferMode) {
        busy = true
        Task {
            let errors = await FileItem.transfer(urls, to: dest, mode: mode)
            busy = false
            if let first = errors.first { alertMessage = first }
            reload()
        }
    }

    func compress(ids: Set<String>) {
        let list = targets(for: ids)
        guard let dir = location, !list.isEmpty else { return }
        let name = list.count == 1 ? "\((list[0].name as NSString).deletingPathExtension).zip" : "Archive.zip"
        let dest = FileItem.uniqueURL(in: dir, name: name)
        busy = true
        Task {
            let ok = await FileItem.zip(list.map(\.name), in: dir, to: dest)
            busy = false
            if !ok { alertMessage = "Couldn't create \(dest.lastPathComponent)." }
            reload()
            selection = [dest.path]
        }
    }

    func openInTerminal(_ url: URL? = nil) {
        guard let dir = url ?? location else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([dir], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    func revealInFinder(ids: Set<String>) {
        let urls = targets(for: ids).map(\.url)
        if urls.isEmpty, let location {
            NSWorkspace.shared.open(location)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    func showProperties(ids: Set<String>) {
        propertiesTarget = targets(for: ids).first ?? location.map(FileItem.init)
    }

    // MARK: - Keyboard

    /// Windows-style keys that SwiftUI menus can't express. Returns true when the key was handled.
    func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        switch event.keyCode {
        case 36, 76: // Return / Enter
            if mods == .option { showProperties(ids: selection); return true }
            guard mods.isEmpty, !selection.isEmpty else { return false }
            openSelection()
        case 51: // Delete (Backspace)
            if mods.isEmpty { goBack() } else if mods == .command { trash(ids: selection) } else { return false }
        case 117: // Forward delete
            guard mods.isEmpty else { return false }
            trash(ids: selection)
        case 120: // F2
            renameSelection()
        case 96: // F5
            reload()
        case 123 where mods == .option: goBack()
        case 124 where mods == .option: goForward()
        case 126 where mods == .option || mods == .command: goUp()
        case 125 where mods == .command: openSelection()
        default:
            return false
        }
        return true
    }
}

/// File clipboard shared by all windows. Writes real file URLs, so copy/paste works with Finder too.
final class FileClipboard: ObservableObject {
    static let shared = FileClipboard()
    @Published private(set) var cutPaths: Set<String> = []
    private var cutChangeCount = -1

    func set(_ urls: [URL], cut: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        cutChangeCount = cut ? pasteboard.changeCount : -1
        cutPaths = cut ? Set(urls.map(\.path)) : []
    }

    func contents() -> (urls: [URL], isCut: Bool) {
        let pasteboard = NSPasteboard.general
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let isCut = pasteboard.changeCount == cutChangeCount
        if !isCut && !cutPaths.isEmpty { cutPaths = [] }
        return (urls, isCut)
    }

    func clearCut() {
        cutChangeCount = -1
        cutPaths = []
    }

    func isCut(_ url: URL) -> Bool { cutPaths.contains(url.path) }
}

/// Routes raw key presses to the model of the window they happened in, unless a text field is being edited.
@MainActor
final class KeyRouter {
    static let shared = KeyRouter()
    private let models = NSHashTable<ExplorerModel>.weakObjects()
    private var monitor: Any?

    func register(_ model: ExplorerModel) { models.add(model) }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { KeyRouter.shared.handle(event) }
            return handled ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window = event.window,
              window.attachedSheet == nil,
              !(window.firstResponder is NSText),
              let model = models.allObjects.first(where: { $0.window === window })
        else { return false }
        return model.handleKey(event)
    }
}

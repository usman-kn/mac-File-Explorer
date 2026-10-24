import AppKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: ExplorerModel
    @State private var volumes = Places.volumes()

    var body: some View {
        List(selection: selection) {
            Section("Quick access") {
                ForEach(Places.quickAccess) { place in
                    Label {
                        Text(place.name)
                    } icon: {
                        Image(systemName: place.symbol).foregroundStyle(place.color)
                    }
                    .tag(place.id)
                }
            }
            Section("This Mac") {
                Label {
                    Text("This Mac")
                } icon: {
                    Image(systemName: "desktopcomputer").foregroundStyle(.blue)
                }
                .tag(Places.thisMacTag)
                ForEach(volumes) { volume in
                    Label {
                        Text(volume.name)
                    } icon: {
                        Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                            .foregroundStyle(.gray)
                    }
                    .tag(volume.id)
                    .contextMenu {
                        if volume.isEjectable {
                            Button("Eject") { eject(volume) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            volumes = Places.volumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            volumes = Places.volumes()
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.location?.path ?? Places.thisMacTag },
            set: { tag in
                guard let tag else { return }
                model.navigate(to: tag == Places.thisMacTag ? nil : URL(fileURLWithPath: tag))
            }
        )
    }

    private func eject(_ volume: Volume) {
        if model.location?.path.hasPrefix(volume.url.path) == true { model.navigate(to: nil) }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }
}

struct FileContentView: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        Group {
            if model.location == nil {
                ThisMacView(model: model)
            } else if let error = model.loadError {
                ContentUnavailableView("Can't open this folder", systemImage: "lock.fill", description: Text(error))
            } else if model.items.isEmpty && !model.isSearching {
                ContentUnavailableView(
                    model.activeQuery.isEmpty ? "This folder is empty." : "No items match your search.",
                    systemImage: model.activeQuery.isEmpty ? "folder" : "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .contextMenu { BackgroundMenu(model: model) }
            } else {
                switch model.viewMode {
                case .details: DetailsView(model: model)
                case .icons: IconGridView(model: model)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { model.drop($0) }
    }
}

struct DetailsView: View {
    @ObservedObject var model: ExplorerModel
    @ObservedObject private var clipboard = FileClipboard.shared

    var body: some View {
        Table(of: FileItem.self, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    FileIcon(url: item.url)
                    Text(model.displayName(item)).lineLimit(1)
                }
                .opacity(clipboard.isCut(item.url) ? 0.45 : (item.isHidden ? 0.6 : 1))
                .help(item.url.path)
            }
            .width(min: 180, ideal: 360)
            TableColumn("Date modified", value: \.modified) { item in
                Text(item.modified, format: Date.FormatStyle(date: .numeric, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 150)
            TableColumn("Type", value: \.typeName) { item in
                Text(item.typeName).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 150)
            TableColumn("Size", value: \.sortSize) { item in
                Text(item.sizeText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 90)
        } rows: {
            ForEach(model.items) { item in
                TableRow(item).itemProvider { NSItemProvider(object: item.url as NSURL) }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            ItemMenu(model: model, ids: ids)
        } primaryAction: { ids in
            model.open(ids: ids)
        }
    }
}

struct IconGridView: View {
    @ObservedObject var model: ExplorerModel
    @ObservedObject private var clipboard = FileClipboard.shared

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 124), spacing: 6)], spacing: 6) {
                ForEach(model.items) { item in
                    let selected = model.selection.contains(item.id)
                    VStack(spacing: 4) {
                        FileIcon(url: item.url, size: 56)
                        Text(model.displayName(item))
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .frame(width: 100, height: 96)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(selected ? Color.accentColor.opacity(0.6) : Color.clear)
                    )
                    .opacity(clipboard.isCut(item.url) ? 0.45 : (item.isHidden ? 0.6 : 1))
                    .contentShape(Rectangle())
                    .help(item.url.path)
                    .onTapGesture(count: 2) { model.open(item) }
                    .onTapGesture { model.click(item) }
                    .onDrag { NSItemProvider(object: item.url as NSURL) }
                    .contextMenu {
                        ItemMenu(model: model, ids: selected ? model.selection : [item.id])
                    }
                }
            }
            .padding(10)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectNone() }
        .contextMenu { BackgroundMenu(model: model) }
    }
}

/// Right-click menu for files and folders.
struct ItemMenu: View {
    let model: ExplorerModel
    let ids: Set<String>

    var body: some View {
        let targets = model.targets(for: ids)
        if targets.isEmpty {
            BackgroundMenu(model: model)
        } else {
            let single = targets.count == 1 ? targets[0] : nil
            Button("Open") { model.open(ids: ids) }
            if let single, !single.isFolder {
                Menu("Open with") {
                    ForEach(NSWorkspace.shared.urlsForApplications(toOpen: single.url).prefix(15), id: \.self) { app in
                        Button {
                            model.open(single.url, with: app)
                        } label: {
                            Label {
                                Text(FileManager.default.displayName(atPath: app.path))
                            } icon: {
                                Image(nsImage: IconCache.shared.icon(for: app, size: 16))
                            }
                        }
                    }
                }
            }
            if let single, single.isFolder {
                Button("Open in Terminal") { model.openInTerminal(single.url) }
            }
            Divider()
            Button("Cut") { model.copy(ids: ids, cut: true) }
            Button("Copy") { model.copy(ids: ids, cut: false) }
            Button("Copy as path") { model.copyPaths(ids: ids) }
            Divider()
            Button("Compress to ZIP file") { model.compress(ids: ids) }
            if let single {
                Button("Rename") { model.startRename(single) }
            }
            Button("Move to Trash") { model.trash(ids: ids) }
            Divider()
            Button("Show in Finder") { model.revealInFinder(ids: ids) }
            if single != nil {
                Button("Properties") { model.showProperties(ids: ids) }
            }
        }
    }
}

/// Right-click menu for empty space in a folder.
struct BackgroundMenu: View {
    let model: ExplorerModel

    var body: some View {
        Menu("View") {
            Button("Details") { model.viewMode = .details }
            Button("Large icons") { model.viewMode = .icons }
        }
        Menu("Sort by") {
            ForEach(SortKey.allCases) { key in
                Button(key.title) { model.sortKey = key }
            }
        }
        Button("Refresh") { model.reload() }
        Divider()
        Button("Paste") { model.paste() }
        Menu("New") {
            Button("Folder") { model.newFolder() }
            Button("Text Document") { model.newTextFile() }
        }
        Divider()
        Button("Open in Terminal") { model.openInTerminal() }
        Button("Copy path") { model.copyPaths(ids: []) }
        Button("Properties") { model.showProperties(ids: []) }
    }
}

/// Overview page listing common folders and drives with free space, like "This PC".
struct ThisMacView: View {
    @ObservedObject var model: ExplorerModel
    @State private var volumes = Places.volumes()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Folders") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                        ForEach(Places.quickAccess) { place in
                            Button { model.navigate(to: place.url) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: place.symbol)
                                        .font(.system(size: 22))
                                        .foregroundStyle(place.color)
                                        .frame(width: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name).font(.system(size: 13, weight: .medium))
                                        Text(place.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                            }
                            .buttonStyle(HoverButtonStyle(padding: 0))
                        }
                    }
                }
                section("Devices and drives") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 8)], spacing: 8) {
                        ForEach(volumes) { volume in
                            Button { model.navigate(to: volume.url) } label: {
                                HStack(spacing: 12) {
                                    FileIcon(url: volume.url, size: 44)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(volume.name).font(.system(size: 13, weight: .medium))
                                        ProgressView(value: volume.usedFraction)
                                            .tint(volume.usedFraction > 0.9 ? .red : .accentColor)
                                        Text("\(bytes(volume.free)) free of \(bytes(volume.total))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(8)
                            }
                            .buttonStyle(HoverButtonStyle(padding: 0))
                        }
                    }
                }
            }
            .padding(20)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            volumes = Places.volumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            volumes = Places.volumes()
        }
    }

    private func bytes(_ n: Int64) -> String { FileItem.sizeFormatter.string(fromByteCount: n) }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}

struct PropertiesView: View {
    let item: FileItem
    @Environment(\.dismiss) private var dismiss
    @State private var folderSummary: (bytes: Int64, files: Int, folders: Int)?

    var body: some View {
        let values = try? item.url.resourceValues(forKeys: [.creationDateKey, .contentAccessDateKey])
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FileIcon(url: item.url, size: 48)
                Text(item.name).font(.title3).textSelection(.enabled)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                row("Type:", item.typeName)
                row("Location:", item.url.deletingLastPathComponent().path)
                if item.isFolder {
                    if let summary = folderSummary {
                        row("Size:", sizeWithBytes(summary.bytes))
                        row("Contains:", "\(summary.files) files, \(summary.folders) folders")
                    } else {
                        row("Size:", "Calculating…")
                    }
                } else {
                    row("Size:", sizeWithBytes(item.size))
                }
                Divider().gridCellColumns(2)
                if let created = values?.creationDate { row("Created:", created.formatted(date: .long, time: .shortened)) }
                row("Modified:", item.modified.formatted(date: .long, time: .shortened))
                if let accessed = values?.contentAccessDate { row("Accessed:", accessed.formatted(date: .long, time: .shortened)) }
            }
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task {
            if item.isFolder { folderSummary = await FileItem.folderSize(item.url) }
        }
    }

    private func sizeWithBytes(_ n: Int64) -> String {
        "\(FileItem.sizeFormatter.string(fromByteCount: n)) (\(n.formatted()) bytes)"
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).lineLimit(2)
        }
    }
}

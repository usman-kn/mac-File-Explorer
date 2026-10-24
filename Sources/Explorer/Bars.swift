import AppKit
import SwiftUI

/// Back / forward / up / refresh, the address bar and the search box.
struct NavigationBar: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        HStack(spacing: 2) {
            navButton("arrow.left", help: "Back (⌥←)", enabled: model.canGoBack, action: model.goBack)
            navButton("arrow.right", help: "Forward (⌥→)", enabled: model.canGoForward, action: model.goForward)
            navButton("arrow.up", help: "Up to parent folder (⌥↑)", enabled: model.canGoUp, action: model.goUp)
            navButton("arrow.clockwise", help: "Refresh (F5)", enabled: true, action: model.reload)
            AddressBar(model: model)
                .padding(.leading, 6)
            SearchBox(model: model)
                .frame(width: 250)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func navButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(HoverButtonStyle(padding: 4))
        .disabled(!enabled)
        .help(help)
    }
}

/// Breadcrumbs that turn into an editable path when you click the empty part of the bar.
struct AddressBar: View {
    @ObservedObject var model: ExplorerModel
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    private struct Segment: Identifiable {
        let name: String
        let url: URL?
        var id: String { url?.path ?? Places.thisMacTag }
    }

    var body: some View {
        Group {
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .padding(.horizontal, 8)
            } else {
                ViewThatFits(in: .horizontal) {
                    crumbs(segments)
                    crumbs(Array(segments.suffix(4)), truncated: true)
                    crumbs(Array(segments.suffix(2)), truncated: true)
                    crumbs(Array(segments.suffix(1)), truncated: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: beginEditing)
            }
        }
        .modifier(FieldBackground(focused: editing))
        .onChange(of: focused) { _, isFocused in
            if !isFocused { editing = false }
        }
        .onChange(of: model.addressFocusRequest) { _, _ in beginEditing() }
    }

    private var segments: [Segment] {
        var result = [Segment(name: "This Mac", url: nil)]
        guard let location = model.location else { return result }
        var url = URL(fileURLWithPath: "/")
        result.append(Segment(name: FileManager.default.displayName(atPath: "/"), url: url))
        for component in location.pathComponents.dropFirst() {
            url.appendPathComponent(component)
            result.append(Segment(name: FileManager.default.displayName(atPath: url.path), url: url))
        }
        return result
    }

    private func crumbs(_ list: [Segment], truncated: Bool = false) -> some View {
        HStack(spacing: 0) {
            Image(systemName: model.location == nil ? "desktopcomputer" : "folder.fill")
                .foregroundStyle(model.location == nil ? Color.blue : Color.yellow)
                .padding(.leading, 8)
                .padding(.trailing, 4)
            if truncated {
                Text("…").foregroundStyle(.secondary)
                chevron
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, segment in
                Button(segment.name) { model.navigate(to: segment.url) }
                    .buttonStyle(HoverButtonStyle(padding: 4))
                    .lineLimit(1)
                    .fixedSize()
                if index < list.count - 1 { chevron }
            }
            Spacer(minLength: 24)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 1)
    }

    private func beginEditing() {
        text = model.location?.path ?? "This Mac"
        editing = true
        DispatchQueue.main.async { focused = true }
    }

    private func commit() {
        let raw = text.trimmingCharacters(in: .whitespaces)
        editing = false
        if raw.isEmpty || raw.caseInsensitiveCompare("This Mac") == .orderedSame {
            model.navigate(to: nil)
        } else {
            model.go(toPath: raw)
        }
    }
}

struct SearchBox: View {
    @ObservedObject var model: ExplorerModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Search \(model.title)", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { model.searchText = "" }
            if model.isSearching {
                ProgressView().controlSize(.small)
            }
            if model.searchText.isEmpty {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            } else {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .modifier(FieldBackground(focused: focused))
        .disabled(model.location == nil)
        .onChange(of: model.searchFocusRequest) { _, _ in focused = true }
    }
}

/// The Windows 11 style command bar: New, clipboard actions, rename, share, delete, sort and view.
struct CommandBar: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        let hasFolder = model.location != nil
        let hasSelection = !model.selection.isEmpty
        HStack(spacing: 2) {
            Menu {
                Button { model.newFolder() } label: { Label("Folder", systemImage: "folder.badge.plus") }
                Button { model.newTextFile() } label: { Label("Text Document", systemImage: "doc.text") }
            } label: {
                Label("New", systemImage: "plus.circle.fill")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 6)
            .disabled(!hasFolder)

            separator
            tool("scissors", "Cut (⌘X)", enabled: hasSelection) { model.copy(ids: model.selection, cut: true) }
            tool("doc.on.doc", "Copy (⌘C)", enabled: hasSelection) { model.copy(ids: model.selection, cut: false) }
            tool("doc.on.clipboard", "Paste (⌘V)", enabled: hasFolder) { model.paste() }
            tool("character.cursor.ibeam", "Rename (F2)", enabled: model.selection.count == 1) { model.renameSelection() }
            ShareLink(items: model.selectedItems.map(\.url)) {
                Image(systemName: "square.and.arrow.up").frame(width: 18, height: 18)
            }
            .buttonStyle(HoverButtonStyle())
            .disabled(!hasSelection)
            .help("Share")
            tool("trash", "Move to Trash (⌘⌫)", enabled: hasSelection) { model.trash(ids: model.selection) }
            separator

            Menu {
                Picker("Sort by", selection: Binding(get: { model.sortKey }, set: { model.sortKey = $0 })) {
                    ForEach(SortKey.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("Order", selection: Binding(get: { model.sortAscending }, set: { model.sortAscending = $0 })) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 6)

            Menu {
                Picker("Layout", selection: $model.viewMode) {
                    Label("Details", systemImage: "list.bullet").tag(ViewMode.details)
                    Label("Large icons", systemImage: "square.grid.2x2").tag(ViewMode.icons)
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Hidden items", isOn: $model.showHidden)
                Toggle("File name extensions", isOn: $model.showExtensions)
            } label: {
                Label("View", systemImage: model.viewMode == .details ? "list.bullet" : "square.grid.2x2")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 6)

            Spacer()

            Menu {
                Button("Select all") { model.selectAll() }
                Button("Select none") { model.selectNone() }
                Button("Invert selection") { model.invertSelection() }
                Divider()
                Button("Copy as path") { model.copyPaths(ids: model.selection) }
                Button("Open in Terminal") { model.openInTerminal() }.disabled(!hasFolder)
                Button("Show in Finder") { model.revealInFinder(ids: model.selection) }.disabled(!hasFolder)
                Divider()
                Button("Properties") { model.showProperties(ids: model.selection) }.disabled(!hasFolder && !hasSelection)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var separator: some View {
        Divider().frame(height: 18).padding(.horizontal, 4)
    }

    private func tool(_ symbol: String, _ help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 18, height: 18)
        }
        .buttonStyle(HoverButtonStyle())
        .disabled(!enabled)
        .help(help)
    }
}

struct StatusBar: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        HStack(spacing: 14) {
            if model.location != nil {
                Text(count(model.items.count))
                if !model.selection.isEmpty {
                    let selected = model.selectedItems
                    let bytes = selected.filter { !$0.isFolder }.reduce(Int64(0)) { $0 + $1.size }
                    Text("\(count(selected.count)) selected" + (bytes > 0 ? "  \(FileItem.sizeFormatter.string(fromByteCount: bytes))" : ""))
                }
            }
            if model.isSearching {
                HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Searching…") }
            }
            if model.busy {
                HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Working…") }
            }
            Spacer()
            HStack(spacing: 0) {
                modeButton(.details, "list.bullet", "Details (⌘1)")
                modeButton(.icons, "square.grid.2x2", "Large icons (⌘2)")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    private func count(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }

    private func modeButton(_ mode: ViewMode, _ symbol: String, _ help: String) -> some View {
        Button { model.viewMode = mode } label: {
            Image(systemName: symbol)
                .foregroundStyle(model.viewMode == mode ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(HoverButtonStyle(padding: 4))
        .help(help)
    }
}

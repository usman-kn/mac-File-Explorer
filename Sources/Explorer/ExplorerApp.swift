import AppKit
import SwiftUI

@main
struct ExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ExplorerWindow()
        }
        .defaultSize(width: 1120, height: 700)
        .commands { ExplorerCommands() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        MainActor.assumeIsolated { KeyRouter.shared.install() }
    }
}

/// Sends an editing action to the focused text field, if there is one. Lets the Edit menu
/// work on text in the address/search bars and on files everywhere else.
@MainActor
private func sendToTextField(_ action: Selector) -> Bool {
    guard NSApp.keyWindow?.firstResponder is NSText else { return false }
    NSApp.sendAction(action, to: nil, from: nil)
    return true
}

struct ExplorerCommands: Commands {
    @FocusedObject private var model: ExplorerModel?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n")
            Button("New Tab") { openTab() }
                .keyboardShortcut("t")
            Divider()
            Button("New Folder") { model?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Text Document") { model?.newTextFile() }
            Divider()
            Button("Properties") { model.map { $0.showProperties(ids: $0.selection) } }
                .keyboardShortcut("i")
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                if !sendToTextField(#selector(NSText.cut(_:))), let model { model.copy(ids: model.selection, cut: true) }
            }
            .keyboardShortcut("x")
            Button("Copy") {
                if !sendToTextField(#selector(NSText.copy(_:))), let model { model.copy(ids: model.selection, cut: false) }
            }
            .keyboardShortcut("c")
            Button("Paste") {
                if !sendToTextField(#selector(NSText.paste(_:))) { model?.paste() }
            }
            .keyboardShortcut("v")
            Button("Copy as Path") { model.map { $0.copyPaths(ids: $0.selection) } }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Divider()
            Button("Select All") {
                if !sendToTextField(#selector(NSText.selectAll(_:))) { model?.selectAll() }
            }
            .keyboardShortcut("a")
            Button("Select None") { model?.selectNone() }
            Button("Invert Selection") { model?.invertSelection() }
            Divider()
            Button("Rename") { model?.renameSelection() }
            Button("Move to Trash") {
                if !sendToTextField(#selector(NSResponder.deleteToBeginningOfLine(_:))), let model {
                    model.trash(ids: model.selection)
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button("Search") { model?.searchFocusRequest += 1 }
                .keyboardShortcut("f")
        }

        CommandGroup(after: .toolbar) {
            Button("Details") { model?.viewMode = .details }
                .keyboardShortcut("1")
            Button("Large Icons") { model?.viewMode = .icons }
                .keyboardShortcut("2")
            Divider()
            Button(model?.showHidden == true ? "Hide Hidden Items" : "Show Hidden Items") { model?.showHidden.toggle() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button(model?.showExtensions == true ? "Hide File Name Extensions" : "Show File Name Extensions") {
                model?.showExtensions.toggle()
            }
            Divider()
        }

        CommandMenu("Go") {
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]")
            Button("Up One Level") { model?.goUp() }
                .keyboardShortcut(.upArrow)
            Button("Refresh") { model?.reload() }
                .keyboardShortcut("r")
            Button("Go to Address…") { model?.addressFocusRequest += 1 }
                .keyboardShortcut("l")
            Divider()
            Button("This Mac") { model?.navigate(to: nil) }
            ForEach(Places.quickAccess) { place in
                Button(place.name) { model?.navigate(to: place.url) }
            }
            Divider()
            Button("Open in Terminal") { model?.openInTerminal() }
            Button("Show in Finder") { model.map { $0.revealInFinder(ids: $0.selection) } }
        }
    }

    /// Opens a new window and merges it into the current window's tab bar.
    private func openTab() {
        guard let current = NSApp.keyWindow else { openWindow(id: "main"); return }
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let new = NSApp.windows.first(where: { !existing.contains(ObjectIdentifier($0)) && $0.canBecomeMain })
            else { return }
            current.addTabbedWindow(new, ordered: .above)
            new.makeKeyAndOrderFront(nil)
        }
    }
}

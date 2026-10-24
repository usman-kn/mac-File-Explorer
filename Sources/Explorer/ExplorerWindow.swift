import AppKit
import SwiftUI

struct ExplorerWindow: View {
    @StateObject private var model = ExplorerModel()

    var body: some View {
        VStack(spacing: 0) {
            NavigationBar(model: model)
            CommandBar(model: model)
            Divider()
            HSplitView {
                SidebarView(model: model)
                    .frame(minWidth: 170, idealWidth: 220, maxWidth: 340)
                FileContentView(model: model)
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            StatusBar(model: model)
        }
        .frame(minWidth: 780, minHeight: 440)
        .navigationTitle(model.title)
        .focusedSceneObject(model)
        .background(WindowAccessor { model.window = $0 })
        .alert("Rename", isPresented: isPresent($model.renameTarget)) {
            TextField("Name", text: $model.renameText)
            Button("Rename") { model.commitRename() }
            Button("Cancel", role: .cancel) { model.renameTarget = nil }
        }
        .alert("Explorer", isPresented: isPresent($model.alertMessage)) {
            Button("OK") {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .sheet(item: $model.propertiesTarget) { PropertiesView(item: $0) }
    }

    private func isPresent<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }
}

/// Hands the hosting NSWindow back to SwiftUI so key presses can be routed per window.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}

/// Flat button that highlights on hover, like Explorer's toolbar buttons.
struct HoverButtonStyle: ButtonStyle {
    var padding: CGFloat = 6

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        HoverBody(configuration: configuration, padding: padding)
    }

    private struct HoverBody: View {
        let configuration: ButtonStyleConfiguration
        let padding: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, padding)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : (hovering && isEnabled ? 0.08 : 0)))
                )
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct FileIcon: View {
    let url: URL
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: IconCache.shared.icon(for: url, size: size))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Rounded field background shared by the address bar and search box.
struct FieldBackground: ViewModifier {
    var focused: Bool

    func body(content: Content) -> some View {
        content
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(focused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: focused ? 1.5 : 1)
            )
    }
}

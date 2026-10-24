# Explorer for Mac

A file manager for macOS laid out like the Windows 11 File Explorer, for people who'd rather not use Finder.
Native SwiftUI app with no dependencies, no network access and no telemetry.

## Features

- **Address bar** with clickable breadcrumbs; click the empty area (or press ⌘L) to type a path. `~` works.
- **Search box** that searches the current folder and every folder below it.
- **Command bar:** New folder / text document, cut, copy, paste, rename, share, delete, sort and view.
- **Navigation pane** with Quick access, iCloud Drive and your drives (right-click a removable drive to eject it).
- **This Mac** page listing your folders and drives with free-space bars, like "This PC".
- **Details view** (Name, Date modified, Type, Size, sortable, folders first) and a **Large icons** view.
- Right-click menu: Open, Open with, Copy as path, Compress to ZIP, Rename, Move to Trash, Properties, Open in Terminal.
- Cut items fade until pasted. Copy and paste works with Finder too. Name clashes become `name - Copy.ext`.
- Drag and drop in and out, hidden files and file extension toggles, tabs (⌘T), and the folder refreshes itself when it changes.

## Keyboard shortcuts

| Key | Action |
|---|---|
| Return | Open the selected item |
| delete | Go back (like Backspace on Windows) |
| fn+delete or ⌘⌫ | Move to Trash |
| F2 | Rename |
| F5 / ⌘R | Refresh |
| ⌥← / ⌥→ / ⌥↑ | Back / forward / up one folder |
| ⌘L | Edit the address bar |
| ⌘F | Search |
| ⇧⌘N | New folder |
| ⌥Return or ⌘I | Properties |
| ⌘1 / ⌘2 | Details / Large icons |
| ⇧⌘. | Show hidden items |

## Safety

- Delete always **moves items to the Trash**. Explorer never permanently erases anything.
- The app makes no network connections and collects no data.
- macOS asks for permission the first time you open Desktop, Documents or Downloads. That's the system's privacy protection working normally.

## Install

Requires macOS 14 (Sonoma) or later and Apple's command line tools (`xcode-select --install`). Building from source means you can read exactly what you're running.

```bash
git clone https://github.com/usman-kn/mac-explorer.git
cd mac-explorer
./build.sh
cp -R build/Explorer.app /Applications/
```

`build.sh` compiles the app with Swift Package Manager, draws the icon, and ad-hoc signs the bundle. It doesn't download anything.

## Limitations

macOS doesn't let any app fully replace Finder. Finder still draws the desktop, and "Show in Finder" in other apps still opens Finder.

## License

MIT. See [LICENSE](LICENSE).

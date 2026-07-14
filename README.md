# Biruni

By Oxin Studio Inc. A native macOS tribute to Norton Commander (1986),
named for the 10th-century Persian polymath Abu Rayhan al-Biruni:
dual-pane file browsing, the classic blue/cyan/yellow DOS palette, F1-F10
function keys, a pulldown menu bar, a command line, archive browsing, and
a user-configurable F2 menu.

## Download

**[Download Biruni.app](https://github.com/d991d/Biruni/releases/latest)**
— free, from the Releases page. Unzip and drag it to Applications.

There's also a [download page](https://d991d.github.io/Biruni/) with
screenshots and feature highlights.

Biruni isn't notarized yet, so the first launch will show a Gatekeeper
warning ("Biruni' Not Opened"). Right-click the app in Finder, choose
**Open**, then confirm — you only need to do this once.

## Building from source

This is a real Xcode project (`Biruni.xcodeproj`), with a local Swift
package (`NCCore`) for the filesystem/archive/compare logic layer.

1. Open **Xcode** (16 or later; the project targets macOS 12+).
2. **File > Open...** and select `Biruni.xcodeproj`.
3. Xcode resolves the local `NCCore` package dependency automatically.
4. Pick the **Biruni** scheme and **Cmd-R** to build and run.

Signing is set to Automatic — pick your own team under **Signing &
Capabilities** if you want to run it on your own Mac. App Sandbox is
intentionally **off**: Biruni's command line shells out to your real login
shell, which the sandbox blocks.

## Project layout

```
Biruni/          The AppKit UI: panels, function-key bar, pulldown menu,
                  command line, viewer/editor windows, the retro color theme.
NCCore/           Local Swift package - pure Swift logic: directory listing,
                  copy/move/delete/rename, archive browsing (via unzip/tar),
                  directory comparison, user-menu config. No AppKit
                  dependency - portable and testable on its own.
```

## What's implemented

- **Dual panels** with the classic blue background, directories in white
  brackets, archives in magenta, marked files in yellow, and a cyan cursor
  bar on the active panel (dim gray on the inactive one).
- **F1** Help - key reference. **F2** User menu (see below). **F3** Quick
  View (text, or a hex+ASCII dump for binary files), in its own window.
  **F4** built-in editor - opens *in place in the opposite panel* rather
  than a new window (Cmd-S to save, Esc to close). **F5** Copy. **F6**
  Move/Rename (single item: edit the full destination path; multiple
  marked items: move to the other panel). **F7** Make Directory. **F8**
  Delete. **F9** pulldown menu (Left / Files / Commands / Options / Right).
  **F10** Quit.
- **Tab** switches the active panel, **Space** marks/unmarks, **Return**
  opens a directory/archive or, on a regular file, opens it with its
  default macOS application. **Backspace** goes up to `..`.
- **Archives** (`.zip`, `.tar`, `.tar.gz`, `.tgz`) can be entered like a
  folder and browsed read-only; Copy (F5) extracts marked items into the
  other panel. This shells out to the system's `unzip`/`tar` rather than
  linking a compression library, so it needs no third-party dependencies.
- **Compare Directories** (Files menu) marks files that differ or are
  missing between the two panels, the way NC's did.
- **Command line** at the bottom runs shell commands - through your actual
  login shell, so PATH/profile-dependent tools (Homebrew, rbenv/nvm, shell
  functions and aliases) work the same as they do in Terminal - in the
  active panel's folder, like typing at the DOS prompt. Pressing Return
  swaps the whole window to a terminal-style transcript of the command and
  its output, the way DOS-era NC's own shell-out screen worked; any
  keypress or click returns to the panels. F2 user-menu commands use the
  same transcript screen.
- **F2 user menu** reads/writes `~/.config/nc-mac/menu.txt` (format:
  `hotkey|label|shell command`), editable from the Commands menu.

## About the macOS permission prompts

The first time you browse into Desktop, Documents, or Downloads, macOS will
show a one-time "Biruni would like to access..." prompt for each
of those three folders - that's normal Files & Folders privacy protection
(TCC), the same thing happens to any Finder alternative, not a bug. Allow
all three and it won't ask again. If a prompt never appeared and a folder
just wouldn't open, grant it manually in **System Settings > Privacy &
Security > Files and Folders**.

## Known simplifications

- **Dialogs** (rename, copy destination, confirmations, MkDir, Delete) are
  hand-drawn (`RetroDialogs.swift`) in the app's own light-gray/black-border
  style with bracket-style `[ OK ]`/`[Cancel]` buttons, matching the rest of
  the retro UI rather than native macOS `NSAlert` chrome.
- **F9's pulldown menus and the F2 user menu** are hand-drawn (`RetroMenu.swift`)
  in the app's own light-gray/cyan-highlight style rather than native `NSMenu`
  chrome, with mouse and arrow-key/Return/Escape navigation.
- **F3 Quick View** still opens in its own window (`ViewerWindowController`)
  since there's no natural "opposite panel" reason to embed a read-only
  viewer the way F4's editor is embedded.
- Editing or writing *into* an archive isn't supported (matches how DOS-era
  NC worked without a configured packer) - F3/F4 on an archived file extract
  a temp copy first.

## License

© 2026 Oxin Studio Inc. All rights reserved.

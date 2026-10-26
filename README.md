# ClipHistory

A tiny macOS menubar app that keeps your recent text copies (20 by default). Press ⌃⌥V from any app, or click the menubar icon, to open the history; click an entry or press ⌘1–⌘9 to put it back on the clipboard.

- Newest first. Copying the same text again moves it to the top.
- Leading and trailing spaces and newlines are trimmed.
- Skips items that password managers mark as concealed or transient.
- History is kept in `~/Library/Application Support/ClipHistory/history.json`.
- **Settings…** (in the menu) changes the shortcut, how many copies are kept (5–200), and whether it opens at login.

## Build

```bash
./build.sh                       # builds and installs ~/Applications/ClipHistory.app
open ~/Applications/ClipHistory.app
```

To start it at login, tick **Open at login** in Settings….

## Transforms (future)

`Sources/ClipHistory/Transformer.swift` has a `Transformer` protocol and an empty `transformers` list. A transform returns a replacement string (e.g. `4127*123` → `507,621`) or nil. The menu shows the result and copies it back; the original text is in the tooltip.

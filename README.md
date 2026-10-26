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

## Transforms

When a copy matches a transform, the copy is kept and the result is added on top of it as a second entry, and put on the clipboard. Copy `4127*123`, paste, and you get `507,621`; the sum is still one entry down.

- **Math** (`MathTransformer.swift`): `4127*123` → `507,621`. Supports `+ - * / × ÷ ^`, parentheses, decimals and a trailing `=`. Sums that only use `-` or `/` need a space or bracket (`10 / 4`), so dates like `2026-10-26` and `10/26` and phone numbers are left alone.

To add one, implement `Transformer` (return the replacement string, or nil) and add it to `transformers` in `Transformer.swift`.

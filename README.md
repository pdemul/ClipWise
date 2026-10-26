# ClipWise

A tiny macOS menubar app that keeps your recent text copies (20 by default). Press ⌃⌥V from any app, or click the menubar icon, to open the history; click an entry or press ⌘1–⌘9 to put it back on the clipboard.

- Newest first. Copying the same text again moves it to the top.
- Leading and trailing spaces and newlines are trimmed.
- Skips items that password managers mark as concealed or transient.
- History is kept in `~/Library/Application Support/ClipWise/history.json`.
- **Settings…** (in the menu) changes the shortcut, how many copies are kept (5–200), and whether it opens at login.

## Build

```bash
./build.sh                       # builds and installs ~/Applications/ClipWise.app
open ~/Applications/ClipWise.app
```

To start it at login, tick **Open at login** in Settings….

## Transforms

When a copy matches a transform, the copy is kept and the result is added on top of it as a second entry, and put on the clipboard. Copy `4127*123`, paste, and you get `507,621`; the sum is still one entry down.

All transforms live in [`Sources/ClipWise/Transformers/`](Sources/ClipWise/Transformers/), one per file:

- **Math** (`MathTransformer.swift`): `4127*123` → `507,621`. Supports `+ - * / × ÷ ^`, parentheses, decimals and a trailing `=`. Sums that only use `-` or `/` need a space or bracket (`10 / 4`), so dates like `2026-10-26` and `10/26` and phone numbers are left alone.
- **Currency** (`CurrencyTransformer.swift`): `1.23 GBP in USD` → `1.64 USD`. Also `to`/`as`/`into`/`=`, lowercase codes, and `£ $ € ¥` (`£50 to eur`). Uses the day's European Central Bank rates from [frankfurter.dev](https://frankfurter.dev) (free, no key, about 30 major currencies), cached for an hour. Unknown currencies or no network: the copy is left as it is.

### Adding a transform

Add a file to `Sources/ClipWise/Transformers/` with a subclass of `Transformer`, then `./build.sh` and restart the app. That's all: every subclass is found at launch and listed under **Transformers** in Settings, where it can be switched off.

```swift
final class ShoutTransformer: Transformer {
    override class var title: String { "Shout" }
    override class var summary: String { "Copy \"shout hello\" and get HELLO." }

    override func transform(_ text: String) async -> String? {
        text.hasPrefix("shout ") ? text.dropFirst(6).uppercased() : nil
    }
}
```

- Return the new text, or `nil` when the copy isn't for you.
- Keep `summary` to about two short lines; that's what Settings shows.
- Be strict about what you match. Every copy goes through every transform that's switched on, in alphabetical order by title, and the first result wins.
- `transform` is async, so it can look something up online. If you copy something else before it finishes, its result is dropped rather than overwriting your new copy.

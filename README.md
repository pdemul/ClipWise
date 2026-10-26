# ClipWise

A tiny macOS menubar app that keeps your recent text copies (20 by default). Press ⌃⌥V from any app, or click the menubar icon, to open the history; click an entry or press ⌘1–⌘9 to put it back on the clipboard. Copy a sum or a currency amount (`4127*123`, `100 Swedish to GBP=`) and the answer is added on top, ready to paste.

## Install

Needs macOS 14 or later, Apple Silicon or Intel.

1. Download `ClipWise-<version>.zip` from the [latest release](https://github.com/pdemul/ClipWise/releases/latest) and unzip it.
2. Move `ClipWise.app` to your Applications folder and open it.
3. The app isn't notarised by Apple yet, so macOS blocks it the first time. Open **System Settings → Privacy & Security**, scroll down to the message about ClipWise, and click **Open Anyway**. You only need to do this once.

A clipboard icon appears in the menubar. To start it at login, tick **Open at login** in Settings….

- Newest first. Copying the same text again moves it to the top.
- Leading and trailing spaces and newlines are trimmed.
- Skips items that password managers mark as concealed or transient.
- History is kept in `~/Library/Application Support/ClipWise/history.json`.
- **Settings…** (in the menu) changes the shortcut, how many copies are kept (5–200), and whether it opens at login.

## Build

```bash
./build.sh                       # builds and installs ~/Applications/ClipWise.app
open ~/Applications/ClipWise.app
./build.sh --release             # universal build, zipped as build/ClipWise-<version>.zip
```

The version number is `VERSION` at the top of `build.sh`.

## Transforms

When a copy matches a transform, the copy is kept and the result is added on top of it as a second entry, and put on the clipboard. Copy `4127*123`, paste, and you get `507,621`; the sum is still one entry down.

All transforms live in [`Sources/ClipWise/Transformers/`](Sources/ClipWise/Transformers/), one per file:

- **Math** (`MathTransformer.swift`): `4127*123` → `507,621`. Supports `+ - * / × ÷ ^`, parentheses, decimals and a trailing `=`. Sums that only use `-` or `/` need a space or bracket (`10 / 4`), so dates like `2026-10-26` and `10/26` and phone numbers are left alone.
- **Currency** (`CurrencyTransformer.swift`): `1.23 GBP in USD` → `1.64 USD`. Currencies can be codes, symbols or names (`£50 to eur`, `100 Swedish to GBP=`, `50 swiss francs into euros`), joined by `in`/`to`/`as`/`into`/`=`, with an optional trailing `=` or `?`. When one side is an exact code, the other may be loose: abbreviated (`swe`), misspelt (`sweedish`) or wordy (`Swedish Krone`); with no code on either side, both names must be exact, so ordinary sentences aren't converted. Uses the day's European Central Bank rates from [frankfurter.dev](https://frankfurter.dev) (free, no key, about 30 major currencies), cached for an hour. Unknown currencies or no network: the copy is left as it is.

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

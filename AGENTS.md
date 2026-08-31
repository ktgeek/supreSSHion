# AGENTS.md

This file provides guidance to AI Agents when working with code in this repository.

## Building

Primary workflow is Xcode — open `supreSSHion.xcodeproj`.

CLI builds:
```bash
xcodebuild -scheme supreSSHion -configuration Debug build
xcodebuild -scheme supreSSHion -configuration Release build
```

Tests (target `supreSSHionTests`, hosted inside the app via `TEST_HOST`/`BUNDLE_LOADER` so
`@testable import supreSSHion` can see internal types):
```bash
xcodebuild -scheme supreSSHion -configuration Debug -destination 'platform=macOS' test
```

No linting tools, and no external dependencies (no CocoaPods/SPM/Carthage).

## Architecture

Components with a clear layering:

**SupreSSHionApp.swift** — App entry point only: `@main struct SupreSSHionApp: App` wires `MenuBarManager` as the `NSApplicationDelegate` via `@NSApplicationDelegateAdaptor`.

**MenuBarManager.swift** — Menu bar UI (`NSObject, NSApplicationDelegate, NSMenuDelegate`). Owns `AgentSupervisor`, `AboutWindow`, `KeysWindow`, and `ExemptionsWindow`, builds the `NSStatusItem` + `NSMenu` programmatically in `applicationDidFinishLaunching`, and refreshes menu items in `menuWillOpen(_:)`. Implements `applicationWillTerminate(_:)`, calling `AgentSupervisor.removeKeysOnTermination()` — this catches every AppKit-mediated exit (menu Quit, ⌘Q, AppleScript quit, logout/shutdown), not just the Quit menu item's action. `applicationDidFinishLaunching` also installs `DispatchSourceSignal` handlers (`signalSources`) for `SIGTERM`/`SIGINT`/`SIGHUP` that call `NSApplication.terminate(nil)`, routing `killall`/Ctrl-C through the same `applicationWillTerminate` path rather than duplicating removal logic.

**AgentSupervisor.swift** — Central orchestrator (`@Observable`). Registers for system notifications via `DistributedNotificationCenter` (`com.apple.screenIsLocked`, `com.apple.screenIsUnlocked`) and `NSWorkspace.willSleepNotification`. Manages the optional disable timer and instantiates `SSHAgentCommunicator` on demand for each operation. Owns an `ExemptionStore` (`exemptions`) and exposes `isExempt(_:)`/`setExempt(_:for:)` for the UI. `refresh()` is the single entry point for reading agent state: one `getLoadedKeys()` call derives `loadedKeys`, `loadedKeysCount`, `exemptLoadedKeysCount`, `keysLoadedMessage`, and `lastError: AgentError?` together, rather than the two separate round-trip-per-call entry points (`refreshKeysCount()`/`fetchLoadedKeys()`) it replaced. When `getLoadedKeys()` fails, `keysLoadedMessage` reads "Cannot reach ssh-agent" rather than the same "0 keys loaded" a genuinely empty agent would show. `removeSelectedKeys(_:)` removes specific keys by blob (via `SSHAgentCommunicator.removeKeys(blobs:)`, one connection for the batch) and calls `refresh()`. `removeKeysNow()` is a true wipe (used by every user-initiated removal); `removeUnexemptedKeys(refreshAfter:) -> Result<Void, AgentError>` is the automatic path used by lock/timer-expiry and skips exempted keys — if the key list itself can't be fetched, it conservatively removes everything (it can't tell what to spare) but still reports the failure rather than treating it as "no keys." `removeKeysOnTermination()` is the app-quit path — it honors exemptions like `removeUnexemptedKeys()`, but unlike the lock handler it ignores the disable state, since disabling removal must not be a cheaper bypass than quitting outright; it also passes `refreshAfter: false`, since a REQUEST_IDENTITIES round trip to update UI state is wasted on an app that's about to exit. User-initiated failures go through `NotificationPresenter.presentUserInitiatedFailure(_:)` (a blocking `NSAlert`); background-removal failures go through `NotificationPresenter.notifyAutomaticFailure(reason:error:)` (a system notification); a termination-path failure has no time budget for either, so it's recorded via `NotificationPresenter.recordTerminationFailure()` and surfaced at the next launch.

**NotificationPresenter.swift** — Stateless namespace (`enum` with only static members) that routes a failed removal to whichever channel fits how it happened: `presentUserInitiatedFailure(_:)` is a blocking `NSAlert` for a removal the user just triggered; `notifyAutomaticFailure(reason:error:)` posts a `UNUserNotification` for a removal that ran in the background; `recordTerminationFailure()`/`surfacePendingTerminationFailure()` handle the app-quit case, where there's no time budget to show anything — a marker file next to `exemptions.plist` is written on failure and consumed (as a notification) the next time `MenuBarManager.applicationDidFinishLaunching` runs. `requestAuthorization()` is also called there, once, to request notification permission.

**SupresshionState.swift** — In-memory state model only (`@Observable`, no persistence). Tracks two disable modes: infinite (`infinitelyDisabled`) or time-bounded (`disabledUntil: Date`). Exposes `isDisabled` and human-readable status strings for the menu.

**SSHAgentCommunicator.swift** — Pure Swift. Opens a Unix domain socket to `$SSH_AUTH_SOCK` via Darwin POSIX APIs and speaks the SSH agent wire protocol directly: `SSH_AGENTC_REQUEST_IDENTITIES (0x0b)` to list keys, `SSH_AGENTC_REMOVE_IDENTITY (0x12)` to remove a single key by blob, `SSH_AGENTC_REMOVE_ALL_IDENTITIES (0x13)` to clear all. Protocol framing: 4-byte big-endian length prefix + payload. Every request goes through `withConnection(_:)`, which opens one connection and hands its fd to the caller rather than each request opening its own — `removeKeys(blobs: [Data])` uses this to send a batch of `REMOVE_IDENTITY` requests over a single connection instead of reconnecting per key (collecting the last failure, if any, without stopping early). All public methods return `Result<_, AgentError>` rather than silently mapping failure to `nil`/`Void`. `getLoadedKeys()` returns `Result<[SSHKey], AgentError>` (SHA-256 fingerprints computed via CryptoKit; raw key blob stored for use with `removeKey(blob:)`/`removeKeys(blobs:)`), parsing the response through `PayloadCursor`, a bounds-checked reader that returns `nil` instead of trapping on any length-prefixed field that doesn't fit — a malformed or hostile agent response can fail parsing but can't crash the process. The declared message size is rejected above a 256 KiB cap before it can drive an unbounded allocation. `openSocket()` sets a 2-second `SO_RCVTIMEO`/`SO_SNDTIMEO` on the connected socket so a wedged ssh-agent fails fast instead of hanging the caller indefinitely — notably `AgentSupervisor.removeKeysOnTermination()`, which runs under app-termination's limited time budget.

**AgentError.swift** — `enum AgentError: Error, Equatable`, `LocalizedError`-conforming: `.noAuthSock`, `.connectFailed(errno:)`, `.timeout`, `.malformedResponse`, `.agentRefused`. The failure type every `SSHAgentCommunicator` method reports via `Result`.

**AboutWindow.swift** — SwiftUI `AboutView` wrapped in an `NSWindowController` via `NSHostingController`. Shown on demand from `MenuBarManager`.

**SSHKey.swift** — `struct SSHKey: Identifiable` model (type, fingerprint, comment, keyBlob) shared between `AgentSupervisor` and `KeysWindow`. `keyBlob: Data` holds the raw public key bytes required by the `REMOVE_IDENTITY` wire protocol. `id` is computed as `fingerprint` (`"SHA256:" + base64(SHA256(blob))`, unpadded) rather than a generated `UUID()`, so it's stable across fetches — both `ExemptionStore` lookups and `KeysWindow` row selection rely on that stability surviving a refresh.

**KeysWindow.swift** — SwiftUI `KeysView` (Exempt + Type + Fingerprint + Comment columns) wrapped in an `NSWindowController`. Holds a reference to `AgentSupervisor` and observes `loadedKeys` directly for live updates. Rows are targeted for removal via the `Table`'s native selection (click / ⌘-click / ⇧-click) rather than a checkbox column — there is no separate "select" checkbox. The Exempt checkbox toggles a key's exemption immediately via `AgentSupervisor.setExempt(_:for:)`; exempted rows are dimmed. A button bar below the table provides "Remove Selected" (enabled when any rows are selected), "Remove All" (a true wipe, including exempted keys), and "Refresh". `KeysWindow.showWindow` fetches the current key list and raises the window without recreating the hosting controller.

**KeyExemption.swift** — `struct KeyExemption: Codable, Identifiable, Hashable` model (fingerprint, label); `id` is the fingerprint.

**ExemptionStore.swift** — `@Observable` persistence layer for exemptions, the only one in the app. Reads/writes an XML property list at `~/Library/Application Support/supreSSHion/exemptions.plist` (versioned envelope, atomic write). `normalize(_:)` validates and canonicalizes fingerprint input (accepts with or without the `SHA256:` prefix and `=` padding) to the same form `SSHAgentCommunicator` produces, so exemption lookups are a plain string match against `SSHKey.fingerprint`. A corrupt file loads as empty (logged) and is not overwritten until a real mutation occurs, so it isn't silently destroyed.

**ExemptionsWindow.swift** — SwiftUI `ExemptionsView` (Fingerprint + editable Label + Loaded columns) wrapped in an `NSWindowController`, following the same shape as `KeysWindow`. Lists every exemption regardless of whether the key is currently loaded. A text-entry row adds new exemptions via `ExemptionStore.normalize(_:)`, with inline validation errors; a button bar provides "Remove Selected" and "Refresh". Reached from the status menu's "Manage Exemptions…" item, which stays enabled even with zero keys loaded.

The project is pure Swift — no Objective-C, no bridging header. There is no `AppDelegate`, `MainMenu.xib`, or `main.m` — the Swift `@main` attribute on `SupreSSHionApp` provides the entry point.

## Key Behaviors

- `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` are **undocumented** macOS distributed notifications — handle carefully.
- System sleep (`willSleepNotification`) **always re-enables** key removal, overriding any active disable timer. This is intentional.
- The app has no sandbox restrictions (entitlements file is empty), which is required for Unix socket access to ssh-agent.
- Exemptions are honored only by *automatic* removal (screen lock, disable-timer expiry via `AgentSupervisor.removeUnexemptedKeys()`). Every user-initiated removal — the menu's "Remove All Keys", the Keys window's "Remove All" button — is a true wipe that ignores exemptions; only the exemption *entries* persist across it, not the keys themselves.
- App termination (menu Quit, ⌘Q, `killall`/SIGTERM/SIGINT/SIGHUP) removes unexempted keys via `AgentSupervisor.removeKeysOnTermination()`, **regardless of the disable state** — this is intentional, so disabling removal can't be used to make quitting a safe way to leave keys loaded. `SIGKILL`, Force Quit, and crashes cannot be intercepted; this is a known, documented limitation, not a bug to fix.

## Workflow

Always enter plan mode before making any file changes — including source code, configuration, and documentation. Present
the plan and get approval before implementing.

### Commits

Every commit an AI agent authors or co-authors must end with the co-author trailer, matching the rest of the
history:

    Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>

Use the model actually doing the work in the trailer name. Add it when the commit is created — don't leave it
for a later rewrite.

## Releases

Version lives in two places, both in `supreSSHion.xcodeproj/project.pbxproj`, each duplicated across
the Debug and Release build configs of the app target:

- `MARKETING_VERSION` — the user-visible version (e.g. `3.0`). Convention is `MAJOR.MINOR`; add a
  patch component only when a patch release is actually needed.
- `CURRENT_PROJECT_VERSION` — the build number, a plain incrementing integer.

`supreSSHion/Info.plist` derives `CFBundleShortVersionString` and `CFBundleVersion` from those two
settings via `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`, and `AboutWindow.swift` reads
`CFBundleShortVersionString` from the bundle at runtime — don't hardcode a version anywhere else.

Every user-facing change gets an entry in `CHANGELOG.md` (Keep a Changelog format) in the same
commit/session as the change, under an `## [Unreleased]` or upcoming-version heading. When cutting a
release: bump both version settings, finalize the `CHANGELOG.md` heading with the release date, and
tag the release commit `vMAJOR.MINOR` (lightweight tag, e.g. `v3.0`).

## Maintenance

Keep this file up-to-date as the project evolves. When making changes that affect project structure, commands, or
conventions described here, update the relevant sections of this file in the same commit/session.

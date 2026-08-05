# AGENTS.md

This file provides guidance to AI Agents when working with code in this repository.

## Building

Primary workflow is Xcode — open `supreSSHion.xcodeproj`.

CLI builds:
```bash
xcodebuild -scheme supreSSHion -configuration Debug build
xcodebuild -scheme supreSSHion -configuration Release build
```

No tests, no linting tools, and no external dependencies (no CocoaPods/SPM/Carthage).

## Architecture

Components with a clear layering:

**SupreSSHionApp.swift** — App entry point only: `@main struct SupreSSHionApp: App` wires `MenuBarManager` as the `NSApplicationDelegate` via `@NSApplicationDelegateAdaptor`.

**MenuBarManager.swift** — Menu bar UI (`NSObject, NSApplicationDelegate, NSMenuDelegate`). Owns `AgentSupervisor`, `AboutWindow`, `KeysWindow`, and `ExemptionsWindow`, builds the `NSStatusItem` + `NSMenu` programmatically in `applicationDidFinishLaunching`, and refreshes menu items in `menuWillOpen(_:)`.

**AgentSupervisor.swift** — Central orchestrator (`@Observable`). Registers for system notifications via `DistributedNotificationCenter` (`com.apple.screenIsLocked`, `com.apple.screenIsUnlocked`) and `NSWorkspace.willSleepNotification`. Manages the optional disable timer and instantiates `SSHAgentCommunicator` on demand for each operation. Owns an `ExemptionStore` (`exemptions`) and exposes `isExempt(_:)`/`setExempt(_:for:)` for the UI. Owns `keysLoadedMessage`, `loadedKeysCount`, and `exemptLoadedKeysCount` (all updated via `refreshKeysCount()`), and `loadedKeys: [SSHKey]` (updated via `fetchLoadedKeys()`). `removeSelectedKeys(_:)` removes specific keys by blob and refreshes both counts and the list. `removeKeysNow()` is a true wipe (used by every user-initiated removal); `removeUnexemptedKeys()` is the automatic path used by lock/timer-expiry and skips exempted keys.

**SupresshionState.swift** — In-memory state model only (`@Observable`, no persistence). Tracks two disable modes: infinite (`infinitelyDisabled`) or time-bounded (`disabledUntil: Date`). Exposes `isDisabled` and human-readable status strings for the menu.

**SSHAgentCommunicator.swift** — Pure Swift. Opens a Unix domain socket to `$SSH_AUTH_SOCK` via Darwin POSIX APIs and speaks the SSH agent wire protocol directly: `SSH_AGENTC_REQUEST_IDENTITIES (0x0b)` to list keys, `SSH_AGENTC_REMOVE_IDENTITY (0x12)` to remove a single key by blob, `SSH_AGENTC_REMOVE_ALL_IDENTITIES (0x13)` to clear all. Protocol framing: 4-byte big-endian length prefix + payload. `getLoadedKeys()` returns `[SSHKey]` directly (SHA-256 fingerprints computed via CryptoKit; raw key blob stored for use with `removeKey(blob:)`).

**AboutWindow.swift** — SwiftUI `AboutView` wrapped in an `NSWindowController` via `NSHostingController`. Shown on demand from `MenuBarManager`.

**SSHKey.swift** — `struct SSHKey: Identifiable` model (type, fingerprint, comment, keyBlob) shared between `AgentSupervisor` and `KeysWindow`. `keyBlob: Data` holds the raw public key bytes required by the `REMOVE_IDENTITY` wire protocol. `fingerprint` (`"SHA256:" + base64(SHA256(blob))`, unpadded) is the stable identifier used to key exemptions across agent sessions and app launches — `id` is a fresh `UUID()` on every fetch and is not stable.

**KeysWindow.swift** — SwiftUI `KeysView` (checkbox + Exempt + Type + Fingerprint + Comment columns) wrapped in an `NSWindowController`. Holds a reference to `AgentSupervisor` and observes `loadedKeys` directly for live updates. The Exempt checkbox toggles a key's exemption immediately via `AgentSupervisor.setExempt(_:for:)`; exempted rows are dimmed. A button bar below the table provides "Remove Selected" (enabled when any rows are checked), "Remove All" (a true wipe, including exempted keys), and "Refresh". `KeysWindow.showWindow` fetches the current key list and raises the window without recreating the hosting controller.

**KeyExemption.swift** — `struct KeyExemption: Codable, Identifiable, Hashable` model (fingerprint, label); `id` is the fingerprint.

**ExemptionStore.swift** — `@Observable` persistence layer for exemptions, the only one in the app. Reads/writes an XML property list at `~/Library/Application Support/supreSSHion/exemptions.plist` (versioned envelope, atomic write). `normalize(_:)` validates and canonicalizes fingerprint input (accepts with or without the `SHA256:` prefix and `=` padding) to the same form `SSHAgentCommunicator` produces, so exemption lookups are a plain string match against `SSHKey.fingerprint`. A corrupt file loads as empty (logged) and is not overwritten until a real mutation occurs, so it isn't silently destroyed.

**ExemptionsWindow.swift** — SwiftUI `ExemptionsView` (Fingerprint + editable Label + Loaded columns) wrapped in an `NSWindowController`, following the same shape as `KeysWindow`. Lists every exemption regardless of whether the key is currently loaded. A text-entry row adds new exemptions via `ExemptionStore.normalize(_:)`, with inline validation errors; a button bar provides "Remove Selected" and "Refresh". Reached from the status menu's "Manage Exemptions…" item, which stays enabled even with zero keys loaded.

The project is pure Swift — no Objective-C, no bridging header. There is no `AppDelegate`, `MainMenu.xib`, or `main.m` — the Swift `@main` attribute on `SupreSSHionApp` provides the entry point.

## Key Behaviors

- `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` are **undocumented** macOS distributed notifications — handle carefully.
- System sleep (`willSleepNotification`) **always re-enables** key removal, overriding any active disable timer. This is intentional.
- The app has no sandbox restrictions (entitlements file is empty), which is required for Unix socket access to ssh-agent.
- Exemptions are honored only by *automatic* removal (screen lock, disable-timer expiry via `AgentSupervisor.removeUnexemptedKeys()`). Every user-initiated removal — the menu's "Remove All Keys", the Keys window's "Remove All" button — is a true wipe that ignores exemptions; only the exemption *entries* persist across it, not the keys themselves.

## Workflow

Always enter plan mode before making any file changes — including source code, configuration, and documentation. Present
the plan and get approval before implementing.

## Maintenance

Keep this file up-to-date as the project evolves. When making changes that affect project structure, commands, or
conventions described here, update the relevant sections of this file in the same commit/session.

# Changelog

All notable changes to supreSSHion are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Version numbers
follow `MAJOR.MINOR` (no patch component unless a patch release is actually needed).

## [Unreleased]

### Added

- supreSSHion now tells you when it can't reach ssh-agent, instead of that looking identical to
  "no keys loaded." The menu shows "Cannot reach ssh-agent" with the specific reason as a tooltip.
  A removal that fails in the background (screen lock, disable-timer expiry) posts a system
  notification; a removal you triggered yourself gets an alert; a removal that fails during quit
  (no time budget left to show anything) is reported the next time supreSSHion launches instead.

### Fixed

- A wire-protocol response from ssh-agent that didn't match the expected format could crash
  supreSSHion outright, rather than being treated as a failure like any other. Since a crash is
  the one case supreSSHion can't protect against, this silently defeated the app's whole purpose.
- Automatic key removal (screen lock, disable-timer expiry) that couldn't retrieve the current key
  list was treating that failure the same as "no keys are loaded," which could remove exempted
  keys it should have spared, or send a pointless removal request when the agent already held no
  keys.
- Editing a label in Manage Exemptions wrote through to disk on every keystroke, which also
  re-sorted the table by label after each character — so the row being edited would move out from
  under the cursor mid-edit. Labels now commit on Return or when the field loses focus, like a
  normal text field.

## [3.0] - 2026-08-15

### Added

- Key exemptions: mark individual keys to survive automatic removal. Exemptions are stored
  persistently (`~/Library/Application Support/supreSSHion/exemptions.plist`), independent of
  whether the key is currently loaded.
- An Exempt column in the Loaded Keys window, and a "Manage Exemptions…" window/menu item for
  managing exemptions regardless of what's currently loaded.
- Keys are now removed when supreSSHion quits — menu Quit, ⌘Q, logout/shutdown, or
  `SIGTERM`/`SIGINT`/`SIGHUP` (e.g. `killall`) — so quitting can no longer be used to leave keys
  loaded. This honors exemptions but ignores the disable timer, since disabling removal must not
  become a cheaper way to bypass quitting.

### Changed

- Exemptions are honored only by *automatic* removal (screen lock, disable-timer expiry, quit).
  Every user-initiated removal — "Remove All Keys" from the menu, "Remove All" in the Keys
  window — remains a true wipe that ignores exemptions.
- Removed the redundant selection checkbox column from the Loaded Keys window in favor of the
  table's native row selection (click / ⌘-click / ⇧-click).
- `SSHKey.id` is now the key's fingerprint instead of a random UUID, so selection and exemption
  state survive a key-list refresh.

### Fixed

- Added 2-second send/receive timeouts on the ssh-agent socket connection, so a wedged
  `ssh-agent` fails fast instead of hanging indefinitely — notably during the limited time
  budget available at app termination.

### Known limitations

- `SIGKILL`, Force Quit, and crashes cannot be intercepted, so keys are not removed in those
  cases. This is a documented limitation, not a bug.

## [2.1] - 2026-05-04

### Added

- Remove one or more selected keys from the Loaded Keys window, rather than only "Remove All".
- `buildServer.json.example` for SourceKit-LSP setup.

### Changed

- Menu wording and punctuation cleanups around key removal.

## [2.0] - 2026-04-01

### Changed

- `SSHAgentCommunicator` rewritten in pure Swift, speaking the ssh-agent wire protocol directly
  over a Unix domain socket.
- Menu and About window rebuilt in SwiftUI (previously XIB-based).
- `StatusMenuController` refactored to follow the project's coding conventions.

### Added

- A Loaded Keys window showing the keys currently held by the agent.

## [1.1] - 2025-01-13

### Changed

- Project updated to build with a newer Xcode.
- "OS X" renamed to "macOS" throughout the UI and docs.

## [1.0] - 2021-05-10

### Added

- A basic About screen, including the count of currently loaded keys.

### Changed

- Project updated to Xcode 12 / Swift 5.
- `LockingSupervisor` renamed to `AgentSupervisor` to better describe its role.

## [0.9.1] - 2018-04-12

### Added

- Keys are removed when a disable timer expires while the screen is locked.

## [0.9] - 2018-04-11

### Added

- Initial release: remove SSH keys automatically on screen lock, remove them manually from the
  menu, temporarily disable removal for a preset delay, and automatically re-enable removal on
  wake from sleep.

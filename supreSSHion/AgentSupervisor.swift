// MIT License
//
// Copyright (c) 2018-2026 Keith Garner
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import AppKit
import Observation

@Observable
@MainActor
class AgentSupervisor : NSObject {
    let suppressionState: SupresshionState
    let exemptions: ExemptionStore
    var disableTimer: Timer?
    var screenIsLocked = false
    var keysLoadedMessage: String = ""
    var loadedKeysCount: Int = 0
    var exemptLoadedKeysCount: Int = 0
    var loadedKeys: [SSHKey] = []
    // Reflects the outcome of the most recent refresh(), so the UI can
    // distinguish "the agent has no keys loaded" from "the agent could not
    // be reached" instead of both reading as zero keys.
    var lastError: AgentError?

    init(state: SupresshionState, exemptions: ExemptionStore = ExemptionStore()) {
        suppressionState = state
        self.exemptions = exemptions
        super.init()

        // I have searched both the net and apple docs, and can't find
        // this documented other than net posters catching all
        // notifications and determining "com.apple.screenIsLocked" is
        // the event we want here. I'd love to use something properly
        // defined and documented.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(self.screenLockedReceived),
            name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"), object: nil)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(self.screenUnlockedReceived),
            name: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"), object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(self.workplaceWillSleepReceived),
            name: NSWorkspace.willSleepNotification, object: nil)

        refresh()
    }

    @objc func screenLockedReceived() {
        screenIsLocked = true
        if !suppressionState.isDisabled {
            if case .failure(let error) = removeUnexemptedKeys() {
                NotificationPresenter.notifyAutomaticFailure(reason: "the screen locked", error: error)
            }
        }
    }

    @objc func screenUnlockedReceived() {
        screenIsLocked = false
        refresh()
    }

    // sleeping automatically resumes the key removal behavior. When
    // OS X sleeps it issues a sleep notification and then a screen
    // lock notification so we only reset the suppressionState on the
    // sleep notification.
    @objc func workplaceWillSleepReceived() {
        suppressionState.resume()
        timerEarlyExit()
    }

    // A true wipe: every user-initiated removal (menu item, "Remove All" button)
    // ignores exemptions. Only automatic lock/timer removal spares exempted keys;
    // see removeUnexemptedKeys().
    func removeKeysNow() {
        let communicator = SSHAgentCommunicator()
        if case .failure(let error) = communicator.removeKeys() {
            NotificationPresenter.presentUserInitiatedFailure(error)
        }
        refresh()
    }

    // Quitting is an easy way to strand keys in the agent past a lock, so this
    // runs even while removal is disabled - unlike the lock handler, which checks
    // isDisabled. Exemptions are still honored, matching the automatic path.
    func removeKeysOnTermination() {
        NSLog("Removing keys because supreSSHion is quitting")
        timerEarlyExit()
        // There's no time budget left here to show a notification - see
        // NotificationPresenter.recordTerminationFailure(). Skips the
        // post-removal refresh too (refreshAfter: false): the app is about
        // to exit, so that's a REQUEST_IDENTITIES round trip spent updating
        // UI state nothing will see, on the one path where every
        // millisecond of the termination time budget matters.
        if case .failure = removeUnexemptedKeys(refreshAfter: false) {
            NotificationPresenter.recordTerminationFailure()
        }
    }

    @discardableResult
    func removeUnexemptedKeys(refreshAfter: Bool = true) -> Result<Void, AgentError> {
        let communicator = SSHAgentCommunicator()
        switch communicator.getLoadedKeys() {
        case .failure(let error):
            // Can't tell which keys are loaded, so can't selectively spare
            // exempted ones. Removing everything is the conservative choice
            // - leaving keys behind because the list failed would be worse
            // than losing an exemption for this one removal - but the
            // failure itself must still be visible to the caller, not
            // silently swallowed by treating it the same as "no keys."
            NSLog("Failed to list loaded keys before automatic removal (\(error.localizedDescription)); removing all keys")
            let removalResult = communicator.removeKeys()
            if refreshAfter { refresh() }
            if case .failure(let removalError) = removalResult { return .failure(removalError) }
            return .failure(error)

        case .success(let keys):
            guard !keys.isEmpty else {
                if refreshAfter { refresh() }
                return .success(())
            }

            let toRemove = keys.filter { !exemptions.isExempt(fingerprint: $0.fingerprint) }
            let removalResult: Result<Void, AgentError>
            if toRemove.count == keys.count {
                removalResult = communicator.removeKeys()
            } else {
                removalResult = communicator.removeKeys(blobs: toRemove.map { $0.keyBlob })
                NSLog("Kept \(keys.count - toRemove.count) exempted key(s) loaded")
            }
            if refreshAfter { refresh() }
            return removalResult
        }
    }

    func resume() {
        suppressionState.resume()
        timerEarlyExit()
    }

    func disable() {
        suppressionState.disable()
        timerEarlyExit()
    }

    func disable(forInterval: TimeInterval) {
        disableTimer?.invalidate()
        let date = Date() + forInterval
        suppressionState.disable(until: date)

        // Timer's closure isn't statically known to run on the main actor
        // (it fires on whatever run loop it's scheduled against), even
        // though in practice that's always the main run loop here since
        // this method only ever runs on the main actor itself. Task { @MainActor }
        // satisfies the isolation check; the hop is effectively immediate.
        disableTimer = Timer.scheduledTimer(withTimeInterval: forInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.timerExpired()
            }
        }
    }

    @objc func timerExpired() {
        suppressionState.resume()
        disableTimer = nil
        if screenIsLocked {
            NSLog("Removing keys because the screen is locked and the disable timer expired")
            if case .failure(let error) = removeUnexemptedKeys() {
                NotificationPresenter.notifyAutomaticFailure(reason: "the disable timer expired", error: error)
            }
        }
        else {
            NSLog("Not removing keys because the screen is unlocked")
        }
    }

    func timerEarlyExit() {
        disableTimer?.invalidate()
        disableTimer = nil
    }

    // Fetches the loaded-key list once and derives every observable that
    // depends on it - loadedKeys, loadedKeysCount, exemptLoadedKeysCount,
    // keysLoadedMessage, lastError - from that single result. Replaces
    // what used to be two separate entry points (refreshKeysCount() and
    // fetchLoadedKeys()) that each made their own REQUEST_IDENTITIES call,
    // so callers that needed both state and the list - removeSelectedKeys(_:),
    // the Keys window's "Remove All" - were paying for two round trips.
    func refresh() {
        let communicator = SSHAgentCommunicator()
        switch communicator.getLoadedKeys() {
        case .success(let keys):
            lastError = nil
            loadedKeys = keys
            loadedKeysCount = keys.count
            exemptLoadedKeysCount = keys.filter { exemptions.isExempt(fingerprint: $0.fingerprint) }.count
            let implyDialog = loadedKeysCount == 0 ? "" : "…"
            let plural = loadedKeysCount == 1 ? "" : "s"
            let exemptClause = exemptLoadedKeysCount == 0 ? "" : " (\(exemptLoadedKeysCount) exempt)"
            keysLoadedMessage = "\(loadedKeysCount) key\(plural) loaded\(exemptClause)\(implyDialog)"
        case .failure(let error):
            lastError = error
            loadedKeys = []
            loadedKeysCount = 0
            exemptLoadedKeysCount = 0
            keysLoadedMessage = "Cannot reach ssh-agent"
        }
    }

    func removeSelectedKeys(_ keys: [SSHKey]) {
        let communicator = SSHAgentCommunicator()
        if case .failure(let error) = communicator.removeKeys(blobs: keys.map { $0.keyBlob }) {
            NotificationPresenter.presentUserInitiatedFailure(error)
        }
        refresh()
    }

    func isExempt(_ key: SSHKey) -> Bool {
        exemptions.isExempt(fingerprint: key.fingerprint)
    }

    func setExempt(_ exempt: Bool, for key: SSHKey) {
        if exempt {
            exemptions.exempt(fingerprint: key.fingerprint, label: key.comment)
        } else {
            exemptions.unexempt(fingerprint: key.fingerprint)
        }
        refresh()
    }

    deinit {
        // deinit is never actor-isolated, even on a @MainActor class, since
        // Swift can't statically guarantee what thread deallocation happens
        // on. In practice this instance is only ever created, used, and
        // released on the main actor (MenuBarManager, itself @MainActor,
        // holds the only reference for the app's lifetime), so
        // assumeIsolated's runtime assertion is safe here - it traps if
        // that assumption is ever wrong, rather than silently racing.
        MainActor.assumeIsolated {
            timerEarlyExit()
            DistributedNotificationCenter.default().removeObserver(self)
            NSWorkspace.shared.notificationCenter.removeObserver(self)
        }
    }
}



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
class AgentSupervisor : NSObject {
    var supressionState: SupresshionState
    let exemptions: ExemptionStore
    var disableTimer: Timer?
    var screenIsLocked = false
    var keysLoadedMessage: String = ""
    var loadedKeysCount: Int = 0
    var exemptLoadedKeysCount: Int = 0
    var loadedKeys: [SSHKey] = []
    // Reflects the outcome of the most recent attempt to reach ssh-agent
    // (refreshKeysCount()/fetchLoadedKeys()), so the UI can distinguish
    // "the agent has no keys loaded" from "the agent could not be reached"
    // instead of both reading as zero keys.
    var lastError: AgentError?

    init(state: SupresshionState, exemptions: ExemptionStore = ExemptionStore()) {
        supressionState = state
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

        refreshKeysCount()
    }

    @objc func screenLockedReceived() {
        screenIsLocked = true
        if !supressionState.isDisabled {
            if case .failure(let error) = removeUnexemptedKeys() {
                NotificationPresenter.notifyAutomaticFailure(reason: "the screen locked", error: error)
            }
        }
    }

    @objc func screenUnlockedReceived() {
        screenIsLocked = false
        refreshKeysCount()
    }

    // sleeping automatically resumes the key removal behavior. When
    // OS X sleeps it issues a sleep notification and then a screen
    // lock notification so we only reset the supressionState on the
    // sleep notification.
    @objc func workplaceWillSleepReceived() {
        supressionState.resume()
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
        refreshKeysCount()
    }

    // Quitting is an easy way to strand keys in the agent past a lock, so this
    // runs even while removal is disabled - unlike the lock handler, which checks
    // isDisabled. Exemptions are still honored, matching the automatic path.
    func removeKeysOnTermination() {
        NSLog("Removing keys because supreSSHion is quitting")
        timerEarlyExit()
        // There's no time budget left here to show a notification - see
        // NotificationPresenter.recordTerminationFailure().
        if case .failure = removeUnexemptedKeys() {
            NotificationPresenter.recordTerminationFailure()
        }
    }

    @discardableResult
    func removeUnexemptedKeys() -> Result<Void, AgentError> {
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
            refreshKeysCount()
            if case .failure(let removalError) = removalResult { return .failure(removalError) }
            return .failure(error)

        case .success(let keys):
            guard !keys.isEmpty else {
                refreshKeysCount()
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
            refreshKeysCount()
            return removalResult
        }
    }

    func resume() {
        supressionState.resume()
        timerEarlyExit()
    }

    func disable() {
        supressionState.disable()
        timerEarlyExit()
    }

    func disable(forInterval: TimeInterval) {
        disableTimer?.invalidate()
        let date = Date() + forInterval
        supressionState.disable(until: date)

        disableTimer = Timer.scheduledTimer(withTimeInterval: forInterval, repeats: false) { _ in
            self.timerExpired()
        }
    }

    @objc func timerExpired() {
        supressionState.resume()
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

    func refreshKeysCount() {
        let communicator = SSHAgentCommunicator()
        switch communicator.getLoadedKeys() {
        case .success(let rawKeys):
            lastError = nil
            loadedKeysCount = rawKeys.count
            exemptLoadedKeysCount = rawKeys.filter { exemptions.isExempt(fingerprint: $0.fingerprint) }.count
            let implyDialog = loadedKeysCount == 0 ? "" : "…"
            let plural = loadedKeysCount == 1 ? "" : "s"
            let exemptClause = exemptLoadedKeysCount == 0 ? "" : " (\(exemptLoadedKeysCount) exempt)"
            keysLoadedMessage = "\(loadedKeysCount) key\(plural) loaded\(exemptClause)\(implyDialog)"
        case .failure(let error):
            lastError = error
            loadedKeysCount = 0
            exemptLoadedKeysCount = 0
            keysLoadedMessage = "Cannot reach ssh-agent"
        }
    }

    func fetchLoadedKeys() {
        let communicator = SSHAgentCommunicator()
        switch communicator.getLoadedKeys() {
        case .success(let keys):
            lastError = nil
            loadedKeys = keys
        case .failure(let error):
            lastError = error
            loadedKeys = []
        }
    }

    func removeSelectedKeys(_ keys: [SSHKey]) {
        let communicator = SSHAgentCommunicator()
        if case .failure(let error) = communicator.removeKeys(blobs: keys.map { $0.keyBlob }) {
            NotificationPresenter.presentUserInitiatedFailure(error)
        }
        refreshKeysCount()
        fetchLoadedKeys()
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
        refreshKeysCount()
    }

    deinit {
        timerEarlyExit()
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}



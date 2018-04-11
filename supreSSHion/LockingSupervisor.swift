// MIT License
//
// Copyright (c) 2018 Keith Garner
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

class LockingSupervisor : NSObject {
    var supressionState: SupresshionState

    init(state:SupresshionState) {
        supressionState = state
        super.init();

        // I have searched both the net and apple docs, and can't find
        // this documented other than net posters catching all
        // notifications and determining "com.apple.screenIsLocked" is
        // the event we want here. I'd love to use something properly
        // defined and documented.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(self.screenLockedReceived),
            name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"), object: nil)

        NSWorkspace.shared().notificationCenter.addObserver(
            self, selector: #selector(self.workplaceWillSleepReceived),
            name: NSNotification.Name.NSWorkspaceWillSleep, object: nil)
    }

    func screenLockedReceived() {
        NSLog("Received screen lock notification")
        if !supressionState.isDisabled {
            removeKeysNow()
        }
    }

    // sleeping automatically resumes the key removal behavior. When
    // OS X sleeps it issues a sleep notification and then a screen
    // lock notification so we only reset the supressionState on the
    // sleep notification.
    func workplaceWillSleepReceived() {
        NSLog("Received sleeping notification")
        supressionState.resume()
    }

    func removeKeysNow() {
        let sshAgentCommicator = SSHAgentCommunicator();
        sshAgentCommicator.removeKeys()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self);
        NSWorkspace.shared().notificationCenter.removeObserver(self);
    }
}



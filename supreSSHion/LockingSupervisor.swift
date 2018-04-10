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

class LockingSupervisor : NSObject {
    var supressionState: SupresshionState

    init(state:SupresshionState) {
        supressionState = state
        super.init();

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(self.screenLockedReceived),
            name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"), object: nil)
    }

    func screenLockedReceived() {
        NSLog("Received screen lock notification")
        if !supressionState.isDisabled() {
            removeKeysNow()
        }
    }

    func removeKeysNow() {
        let sshAgentCommicator = SSHAgentCommunicator();
        sshAgentCommicator.removeKeys()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self);
    }
}



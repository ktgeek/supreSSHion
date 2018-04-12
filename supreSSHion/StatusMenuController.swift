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

import Cocoa

class StatusMenuController : NSObject, NSMenuDelegate {
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var stateItem: NSMenuItem!
    @IBOutlet weak var resumeItem: NSMenuItem!

    let statusItem = NSStatusBar.system().statusItem(withLength: NSVariableStatusItemLength)
    var supresshionState: SupresshionState
    var lockingSupervisor: LockingSupervisor

    override init() {
        supresshionState = SupresshionState()
        lockingSupervisor = LockingSupervisor(state: supresshionState)
        super.init()
    }

    override func awakeFromNib() {
        let icon = NSImage(named: "statusIcon")
        icon?.isTemplate = true
        statusItem.image = icon
        statusItem.menu = statusMenu
    }

    @IBAction func quitClicked(sender: NSMenuItem) {
        NSApplication.shared().terminate(self)
    }

    // Manually clicking remove keys ALWAYS overrides being disabled
    @IBAction func removeSSHKeysClicked(_ sender: NSMenuItem) {
        lockingSupervisor.removeKeysNow()
    }

    @IBAction func resumeClicked(_ sender: NSMenuItem) {
        lockingSupervisor.resume()
    }

    @IBAction func untilResumedClicked(_ sender: NSMenuItem) {
        lockingSupervisor.disable()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        resumeItem.isHidden = !supresshionState.isDisabled
        stateItem.title = supresshionState.statusMessage
    }

    @IBAction func timeClicked(_ sender: NSMenuItem) {
        lockingSupervisor.disable(forInterval: TimeInterval(sender.tag))
    }

}

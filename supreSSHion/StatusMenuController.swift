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
    @IBOutlet weak var keysItem: NSMenuItem!

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var supresshionState: SupresshionState
    var agentSupervisor: AgentSupervisor
    var aboutWindow: AboutWindow!

    override init() {
        supresshionState = SupresshionState()
        agentSupervisor = AgentSupervisor(state: supresshionState)
        super.init()
    }

    override func awakeFromNib() {
        let icon = NSImage(named: "statusIcon")
        icon?.isTemplate = true
        statusItem.image = icon
        statusItem.menu = statusMenu

        aboutWindow = AboutWindow()
    }

    @IBAction func quitClicked(sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }

    // Manually clicking remove keys ALWAYS overrides being disabled
    @IBAction func removeSSHKeysClicked(_ sender: NSMenuItem) {
        agentSupervisor.removeKeysNow()
    }

    @IBAction func resumeClicked(_ sender: NSMenuItem) {
        agentSupervisor.resume()
    }

    @IBAction func untilResumedClicked(_ sender: NSMenuItem) {
        agentSupervisor.disable()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        resumeItem.isHidden = !supresshionState.isDisabled
        stateItem.title = supresshionState.statusMessage

        keysItem.title = agentSupervisor.keysLoadedMessage
        keysItem.isHidden = false
    }

    @IBAction func timeClicked(_ sender: NSMenuItem) {
        agentSupervisor.disable(forInterval: TimeInterval(sender.tag))
    }

    @IBAction func aboutClicked(_ sender: NSMenuItem) {
        aboutWindow.showWindow(nil)
    }
}

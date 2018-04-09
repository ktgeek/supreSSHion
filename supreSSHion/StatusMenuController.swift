//
//  StatusMenuController.swift
//  supreSSHion
//
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

class StatusMenuController: NSObject {
    @IBOutlet weak var statusMenu: NSMenu!
    
    let statusItem = NSStatusBar.system().statusItem(withLength: NSVariableStatusItemLength)
    // TODO: Allow this to be configurable
    let socketPath = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"];
    
    override func awakeFromNib() {
        let icon = NSImage(named: "statusIcon")
        icon?.isTemplate = true
        statusItem.image = icon
        statusItem.menu = statusMenu;
    }
    
    @IBAction func quitClicked(sender: NSMenuItem) {
        NSApplication.shared().terminate(self)
    }
    
    @IBAction func removeSSHKeysClicked(_ sender: NSMenuItem) {
        let sshAgentCommunicator: SSHAgentCommunicator = SSHAgentCommunicator(socketPath: socketPath);
        sshAgentCommunicator.removeKeys();
    }
}

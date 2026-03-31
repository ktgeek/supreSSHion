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

import Cocoa
import SwiftUI

@main
struct SupreSSHionApp: App {
    @NSApplicationDelegateAdaptor(MenuBarManager.self) var menuBarManager
    var body: some Scene { Settings { EmptyView() } }
}

class MenuBarManager: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let supervisor = AgentSupervisor(state: SupresshionState())
    private var aboutWindow: AboutWindow!

    private weak var stateItem: NSMenuItem?
    private weak var keysItem: NSMenuItem?
    private weak var resumeItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let icon = NSImage(named: "statusIcon")
        icon?.isTemplate = true
        statusItem.button?.image = icon

        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu

        aboutWindow = AboutWindow()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let state = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        state.isEnabled = false
        stateItem = state

        let keys = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        keys.isEnabled = false
        keysItem = keys

        menu.addItem(.separator())

        let resume = menu.addItem(withTitle: "Resume", action: #selector(resumeAction), keyEquivalent: "")
        resume.target = self
        resumeItem = resume

        let disableMenu = NSMenu()
        for (title, interval) in [("for 30 minutes", 1800), ("for 1 hour", 3600),
                                   ("for 2 hours", 7200), ("for 3 hours", 10800)] {
            let item = disableMenu.addItem(withTitle: title, action: #selector(timeAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = interval
        }
        let untilResumed = disableMenu.addItem(withTitle: "until resumed", action: #selector(untilResumedAction), keyEquivalent: "")
        untilResumed.target = self

        let disableItem = menu.addItem(withTitle: "Disable...", action: nil, keyEquivalent: "")
        disableItem.submenu = disableMenu

        menu.addItem(.separator())

        let removeKeys = menu.addItem(withTitle: "Remove SSH Keys", action: #selector(removeSSHKeysAction), keyEquivalent: "")
        removeKeys.target = self

        menu.addItem(.separator())

        let about = menu.addItem(withTitle: "About supreSSHion", action: #selector(aboutAction), keyEquivalent: "")
        about.target = self

        let quit = menu.addItem(withTitle: "Quit", action: #selector(quitAction), keyEquivalent: "")
        quit.target = self

        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        supervisor.refreshKeysCount()
        stateItem?.title = supervisor.supressionState.statusMessage
        keysItem?.title = supervisor.keysLoadedMessage
        resumeItem?.isHidden = !supervisor.supressionState.isDisabled
    }

    @objc private func resumeAction() { supervisor.resume() }
    @objc private func untilResumedAction() { supervisor.disable() }
    @objc private func timeAction(_ sender: NSMenuItem) { supervisor.disable(forInterval: TimeInterval(sender.tag)) }
    @objc private func removeSSHKeysAction() { supervisor.removeKeysNow() }
    @objc private func aboutAction() { aboutWindow.showWindow(nil) }
    @objc private func quitAction() { NSApplication.shared.terminate(self) }
}

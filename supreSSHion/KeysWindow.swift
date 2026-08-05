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

private struct KeysView: View {
    let supervisor: AgentSupervisor
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            Table(supervisor.loadedKeys, selection: $selectedIDs) {
                TableColumn("") { key in
                    Toggle("", isOn: Binding(
                        get: { selectedIDs.contains(key.id) },
                        set: { checked in
                            if checked { selectedIDs.insert(key.id) }
                            else { selectedIDs.remove(key.id) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
                .width(20)
                TableColumn("Exempt") { key in
                    Toggle("", isOn: Binding(
                        get: { supervisor.isExempt(key) },
                        set: { supervisor.setExempt($0, for: key) }
                    ))
                    .toggleStyle(.checkbox)
                    .help("Keep this key loaded when the screen locks or the Mac sleeps")
                }
                .width(52)
                TableColumn("Type") { key in
                    Text(key.type).foregroundStyle(supervisor.isExempt(key) ? .secondary : .primary)
                }
                .width(min: 60, ideal: 110)
                TableColumn("Fingerprint") { key in
                    Text(key.fingerprint)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(supervisor.isExempt(key) ? .secondary : .primary)
                }
                .width(min: 100, ideal: 360)
                TableColumn("Comment") { key in
                    Text(key.comment).foregroundStyle(supervisor.isExempt(key) ? .secondary : .primary)
                }
                .width(min: 40)
            }
            .frame(minHeight: 160)

            Divider()

            HStack {
                Spacer()
                Button("Remove Selected") {
                    let toRemove = supervisor.loadedKeys.filter { selectedIDs.contains($0.id) }
                    supervisor.removeSelectedKeys(toRemove)
                    selectedIDs = []
                }
                .disabled(selectedIDs.isEmpty)

                Button("Remove All") {
                    supervisor.removeKeysNow()
                    supervisor.fetchLoadedKeys()
                    selectedIDs = []
                }
                .disabled(supervisor.loadedKeys.isEmpty)
                .help("Removes every loaded key, including exempted ones")

                Button("Refresh") {
                    supervisor.fetchLoadedKeys()
                }
            }
            .padding(8)
        }
    }
}

class KeysWindow: NSWindowController, NSWindowDelegate {
    private let supervisor: AgentSupervisor

    init(supervisor: AgentSupervisor) {
        self.supervisor = supervisor
        let window = NSWindow(
            contentViewController: NSHostingController(rootView: KeysView(supervisor: supervisor))
        )
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "Loaded SSH Keys"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func showWindow(_ sender: Any?) {
        supervisor.fetchLoadedKeys()
        if !(window?.isVisible ?? false) {
            window?.setContentSize(NSSize(width: 760, height: 250))
            window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

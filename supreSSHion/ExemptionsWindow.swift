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

private struct ExemptionsView: View {
    let supervisor: AgentSupervisor
    @State private var selectedIDs: Set<String> = []
    @State private var newFingerprint: String = ""
    @State private var newLabel: String = ""
    @State private var errorMessage: String?

    private var loadedFingerprints: Set<String> {
        Set(supervisor.loadedKeys.map { $0.fingerprint })
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(supervisor.exemptions.exemptions, selection: $selectedIDs) {
                TableColumn("Fingerprint") { exemption in
                    Text(exemption.fingerprint).font(.system(.body, design: .monospaced))
                }
                .width(min: 100, ideal: 360)
                TableColumn("Label") { exemption in
                    TextField("", text: Binding(
                        get: { exemption.label },
                        set: { supervisor.exemptions.setLabel($0, for: exemption.fingerprint) }
                    ))
                    .textFieldStyle(.plain)
                }
                .width(min: 80, ideal: 180)
                TableColumn("Loaded") { exemption in
                    let loaded = loadedFingerprints.contains(exemption.fingerprint)
                    Text(loaded ? "Yes" : "No")
                        .foregroundStyle(loaded ? .primary : .secondary)
                }
                .width(50)
            }
            .frame(minHeight: 160)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("SHA256:… (from ssh-add -l)", text: $newFingerprint)
                        .font(.system(.body, design: .monospaced))
                    TextField("Label (optional)", text: $newLabel)
                        .frame(width: 180)
                    Button("Add") { addExemption() }
                        .disabled(newFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(8)

            Divider()

            HStack {
                Spacer()
                Button("Remove Selected") {
                    for fingerprint in selectedIDs { supervisor.exemptions.unexempt(fingerprint: fingerprint) }
                    selectedIDs = []
                    supervisor.refresh()
                }
                .disabled(selectedIDs.isEmpty)

                Button("Refresh") { supervisor.refresh() }
            }
            .padding(8)
        }
    }

    private func addExemption() {
        guard let fingerprint = ExemptionStore.normalize(newFingerprint) else {
            errorMessage = "Not a valid SHA-256 fingerprint — paste the SHA256:… value shown by ssh-add -l."
            return
        }
        supervisor.exemptions.exempt(fingerprint: fingerprint, label: newLabel)
        supervisor.refresh()
        newFingerprint = ""
        newLabel = ""
        errorMessage = nil
    }
}

class ExemptionsWindow: NSWindowController, NSWindowDelegate {
    private let supervisor: AgentSupervisor

    init(supervisor: AgentSupervisor) {
        self.supervisor = supervisor
        let window = NSWindow(
            contentViewController: NSHostingController(rootView: ExemptionsView(supervisor: supervisor))
        )
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "SSH Key Exemptions"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func showWindow(_ sender: Any?) {
        supervisor.refresh()
        if !(window?.isVisible ?? false) {
            window?.setContentSize(NSSize(width: 760, height: 300))
            window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

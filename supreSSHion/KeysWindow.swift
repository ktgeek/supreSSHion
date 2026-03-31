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

private func measureWidth(strings: [String], header: String,
                          font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)) -> CGFloat {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    return (([header] + strings).map {
        NSAttributedString(string: $0, attributes: attrs).size().width
    }.max() ?? 0) + 8
}

private struct KeysView: View {
    let keys: [SSHKey]
    let typeWidth: CGFloat
    let fingerprintWidth: CGFloat
    let commentWidth: CGFloat

    var body: some View {
        Table(keys) {
            TableColumn("Type") { Text($0.type) }
                .width(min: 40, ideal: typeWidth)
            TableColumn("Fingerprint") { Text($0.fingerprint).font(.system(.body, design: .monospaced)) }
                .width(min: 40, ideal: fingerprintWidth)
            TableColumn("Comment") { Text($0.comment) }
                .width(min: 40, ideal: commentWidth)
        }
        .frame(minHeight: 160)
    }
}

class KeysWindow: NSWindowController, NSWindowDelegate {
    private let supervisor: AgentSupervisor

    init(supervisor: AgentSupervisor) {
        self.supervisor = supervisor
        let window = NSWindow(
            contentViewController: NSHostingController(rootView: KeysView(
                keys: [], typeWidth: 0, fingerprintWidth: 0, commentWidth: 0))
        )
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "Loaded SSH Keys"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func showWindow(_ sender: Any?) {
        let keys     = supervisor.loadedKeys
        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let monoFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let typeWidth        = measureWidth(strings: keys.map(\.type),        header: "Type",        font: bodyFont)
        let fingerprintWidth = measureWidth(strings: keys.map(\.fingerprint), header: "Fingerprint", font: monoFont)
        let commentWidth     = measureWidth(strings: keys.map(\.comment),     header: "Comment",     font: bodyFont)

        let contentWidth = min(typeWidth + fingerprintWidth + commentWidth + 60, 1100)
        window?.contentViewController = NSHostingController(rootView: KeysView(
            keys: keys,
            typeWidth: typeWidth,
            fingerprintWidth: fingerprintWidth,
            commentWidth: commentWidth
        ))
        window?.setContentSize(NSSize(width: contentWidth, height: 200))
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

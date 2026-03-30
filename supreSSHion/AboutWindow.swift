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

private struct AboutView: View {
    let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    let projectURL = URL(string: "https://github.com/ktgeek/supreSSHion")!

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image("AboutImage")
                .resizable()
                .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("supreSSHion")
                        .font(.headline)
                    Text(version)
                        .foregroundStyle(.secondary)
                }

                Link("https://github.com/ktgeek/supreSSHion", destination: projectURL)

                Spacer()

                Text("© 2020-2026 Keith T. Garner")
                    .font(.caption)
                Text("MIT License")
                    .font(.caption)
                Text("App icon \"Forget\" by Gregor Cresnar from the Noun Project, licensed under CC BY.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 44)
        .frame(width: 460, height: 168)
    }
}

class AboutWindow: NSWindowController, NSWindowDelegate {
    convenience init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        window.styleMask = [.titled, .closable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

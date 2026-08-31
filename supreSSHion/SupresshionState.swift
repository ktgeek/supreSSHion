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

import Foundation
import Observation

@Observable
class SupresshionState {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var infinitelyDisabled = false
    private var disabledUntil: Date?

    var isDisabled: Bool {
        if infinitelyDisabled { return true }
        guard let disabledUntil else { return false }
        return disabledUntil > Date()
    }

    var statusMessage: String {
        guard isDisabled else { return "Active" }
        guard !infinitelyDisabled else { return "Disabled" }
        // isDisabled being true and infinitelyDisabled being false means
        // disabledUntil must be a non-nil future date; this fallback is
        // unreachable in practice but avoids force-unwrapping it.
        guard let disabledUntil else { return "Disabled" }
        return "Disabled until \(SupresshionState.timeFormatter.string(from: disabledUntil))"
    }

    func disable() {
        infinitelyDisabled = true
        disabledUntil = nil
    }

    func disable(until: Date) {
        disabledUntil = until
        infinitelyDisabled = false
    }

    func resume() {
        infinitelyDisabled = false
        disabledUntil = nil
    }
}

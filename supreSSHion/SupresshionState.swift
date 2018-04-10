//// MIT License
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

class SupresshionState : NSObject {

    private var manuallyDisabled = false
    private var disabledUntil: Date?

    func isDisabled() -> Bool {
        if manuallyDisabled {
            return true
        }

        return disabledUntil != nil ? (disabledUntil! > Date()) : false
    }

    func statusMessage() -> String {
        if !isDisabled() {
            return "Active"
        }

        if manuallyDisabled {
            return "Disabled"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        return "Disabled until \(dateFormatter.string(from: disabledUntil!))"
    }

    func disable() {
        manuallyDisabled = true
        disabledUntil = nil
    }

    func disable(until:Date) {
        disabledUntil = until
        manuallyDisabled = false
    }

    func resume() {
        manuallyDisabled = false
        disabledUntil = nil
    }
}
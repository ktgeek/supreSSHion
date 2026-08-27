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

import XCTest
@testable import supreSSHion

final class SupresshionStateTests: XCTestCase {
    func testStartsActiveAndNotDisabled() {
        let state = SupresshionState()
        XCTAssertFalse(state.isDisabled)
        XCTAssertEqual(state.statusMessage, "Active")
    }

    func testDisableIsInfiniteAndOverridesAnyPriorTimer() {
        let state = SupresshionState()
        state.disable(until: Date().addingTimeInterval(300))
        state.disable()

        XCTAssertTrue(state.isDisabled)
        XCTAssertEqual(state.statusMessage, "Disabled")
    }

    func testDisableUntilFutureDateIsDisabled() {
        let state = SupresshionState()
        state.disable(until: Date().addingTimeInterval(300))

        XCTAssertTrue(state.isDisabled)
        XCTAssertTrue(state.statusMessage.hasPrefix("Disabled until "))
    }

    func testDisableUntilPastDateIsNotDisabled() {
        let state = SupresshionState()
        state.disable(until: Date().addingTimeInterval(-1))

        XCTAssertFalse(state.isDisabled)
        XCTAssertEqual(state.statusMessage, "Active")
    }

    func testResumeClearsInfiniteDisable() {
        let state = SupresshionState()
        state.disable()
        state.resume()

        XCTAssertFalse(state.isDisabled)
        XCTAssertEqual(state.statusMessage, "Active")
    }

    func testResumeClearsTimedDisable() {
        let state = SupresshionState()
        state.disable(until: Date().addingTimeInterval(300))
        state.resume()

        XCTAssertFalse(state.isDisabled)
        XCTAssertEqual(state.statusMessage, "Active")
    }

    func testDisableUntilAfterInfiniteDisableIsTimeBounded() {
        // Switching from an infinite disable to a timed one should drop the
        // infinite flag, not leave both set.
        let state = SupresshionState()
        state.disable()
        state.disable(until: Date().addingTimeInterval(300))

        XCTAssertTrue(state.isDisabled)
        XCTAssertTrue(state.statusMessage.hasPrefix("Disabled until "))
    }
}

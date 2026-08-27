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

final class ExemptionStoreNormalizeTests: XCTestCase {
    // A real SHA-256 digest, base64 encoded without padding, as SSHAgentCommunicator
    // and ssh-add -l would print it.
    private let canonical = "SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU"
    private let rawBase64 = "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU"

    func testAlreadyCanonicalRoundTrips() {
        XCTAssertEqual(ExemptionStore.normalize(canonical), canonical)
    }

    func testAcceptsWithoutPrefix() {
        XCTAssertEqual(ExemptionStore.normalize(rawBase64), canonical)
    }

    func testPrefixIsCaseInsensitive() {
        XCTAssertEqual(ExemptionStore.normalize("sha256:" + rawBase64), canonical)
        XCTAssertEqual(ExemptionStore.normalize("Sha256:" + rawBase64), canonical)
    }

    func testAcceptsWithPadding() {
        // 43 base64 chars for a 32-byte digest needs one '=' to pad to a multiple of 4.
        XCTAssertEqual(ExemptionStore.normalize("SHA256:" + rawBase64 + "="), canonical)
    }

    func testTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(ExemptionStore.normalize("  \(canonical)  \n"), canonical)
    }

    func testRejectsNonBase64Input() {
        XCTAssertNil(ExemptionStore.normalize("SHA256:not-valid-base64!!!"))
    }

    func testRejectsWrongLengthDigest() {
        // Valid base64, but decodes to fewer than 32 bytes.
        XCTAssertNil(ExemptionStore.normalize("SHA256:AAAA"))
    }

    func testRejectsEmptyInput() {
        XCTAssertNil(ExemptionStore.normalize(""))
        XCTAssertNil(ExemptionStore.normalize("   "))
    }

    func testRejectsMD5StyleFingerprint() {
        // The legacy ssh-keygen MD5 hex format must not be accepted as SHA-256.
        XCTAssertNil(ExemptionStore.normalize("MD5:aa:bb:cc:dd"))
    }
}

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

import CryptoKit
import XCTest
@testable import supreSSHion

/// Regression tests for the getLoadedKeys() wire-protocol parser. Each
/// malformed-input case here previously either crashed the process (a
/// Range-out-of-bounds trap) or, for the embedded key-type field, could
/// read past a key blob's own bounds. After the PayloadCursor rewrite, every
/// one of these must fail cleanly - getLoadedKeys() returns nil - rather
/// than trap.
final class SSHAgentCommunicatorParserTests: XCTestCase {
    private func expectedFingerprint(for blob: Data) -> String {
        let digest = SHA256.hash(data: blob)
        let b64 = Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:" + b64
    }

    // MARK: - Baseline: a well-formed multi-key response parses correctly

    func testWellFormedMultiKeyResponseParsesCorrectly() throws {
        let blob1 = FakeAgentResponse.validBlob(type: "ssh-ed25519", keyMaterial: Data([0x01, 0x02, 0x03]))
        let blob2 = FakeAgentResponse.validBlob(type: "ssh-rsa", keyMaterial: Data([0x04, 0x05, 0x06, 0x07]))
        let entries = FakeAgentResponse.lengthPrefixed(blob1) + FakeAgentResponse.lengthPrefixed("user@host1")
            + FakeAgentResponse.lengthPrefixed(blob2) + FakeAgentResponse.lengthPrefixed("user@host2")
        let response = FakeAgentResponse.identitiesAnswer(nKeys: 2, entries: entries)

        let agent = try FakeSSHAgent()
        agent.respondOnce(with: response)
        let keys = SSHAgentCommunicator(socketPath: agent.socketPath).getLoadedKeys()

        XCTAssertEqual(keys?.count, 2)
        XCTAssertEqual(keys?[0].type, "ssh-ed25519")
        XCTAssertEqual(keys?[0].comment, "user@host1")
        XCTAssertEqual(keys?[0].fingerprint, expectedFingerprint(for: blob1))
        XCTAssertEqual(keys?[0].keyBlob, blob1)
        XCTAssertEqual(keys?[1].type, "ssh-rsa")
        XCTAssertEqual(keys?[1].comment, "user@host2")
        XCTAssertEqual(keys?[1].fingerprint, expectedFingerprint(for: blob2))
    }

    func testEmptyIdentityListParsesToEmptyArray() throws {
        let response = FakeAgentResponse.identitiesAnswer(nKeys: 0, entries: Data())

        let agent = try FakeSSHAgent()
        agent.respondOnce(with: response)
        let keys = SSHAgentCommunicator(socketPath: agent.socketPath).getLoadedKeys()

        XCTAssertEqual(keys?.count, 0)
    }

    // MARK: - H1 regressions

    func testOversizedEmbeddedTypeLengthReturnsNilNotCrash() throws {
        // The blob's embedded type-length field claims a string far larger
        // than any bytes actually present in the blob.
        var blob = FakeAgentResponse.bigEndianBytes(0xFFFF_FFFF)
        blob.append(Data([0x01, 0x02, 0x03]))
        let entries = FakeAgentResponse.lengthPrefixed(blob) + FakeAgentResponse.lengthPrefixed("user@host")
        let response = FakeAgentResponse.identitiesAnswer(nKeys: 1, entries: entries)

        let agent = try FakeSSHAgent()
        agent.respondOnce(with: response)
        let keys = SSHAgentCommunicator(socketPath: agent.socketPath).getLoadedKeys()

        XCTAssertNil(keys)
    }

    func testShortFinalBlobReturnsNilNotCrash() throws {
        // A blob too short to even hold its own embedded type-length field
        // (needs 4 bytes; this has 2), with nothing following it - as if
        // this were a truncated final entry.
        let blob = Data([0x00, 0x01])
        let entries = FakeAgentResponse.lengthPrefixed(blob)
        let response = FakeAgentResponse.identitiesAnswer(nKeys: 1, entries: entries)

        let agent = try FakeSSHAgent()
        agent.respondOnce(with: response)
        let keys = SSHAgentCommunicator(socketPath: agent.socketPath).getLoadedKeys()

        XCTAssertNil(keys)
    }

    func testOversizedDeclaredMessageSizeReturnsNilNotCrash() throws {
        // Declares a message far above the 256 KiB cap without actually
        // sending anywhere near that much data - the cap must reject this
        // before attempting to allocate for it.
        let response = FakeAgentResponse.identitiesAnswer(nKeys: 0, entries: Data(), overrideMsgLen: 10 * 1024 * 1024)

        let agent = try FakeSSHAgent()
        agent.respondOnce(with: response)
        let keys = SSHAgentCommunicator(socketPath: agent.socketPath).getLoadedKeys()

        XCTAssertNil(keys)
    }

    func testTruncatedCommentFieldReturnsNilNotCrash() throws {
        let blob = FakeAgentResponse.validBlob(type: "ssh-ed25519")
        var entries = FakeAgentResponse.lengthPrefixed(blob)
        // Declares a 500-byte comment but supplies only 2 bytes for it.
        entries += FakeAgentResponse.bigEndianBytes(500) + Data([0x01, 0x02])
        let response = FakeAgentResponse.identitiesAnswer(nKeys: 1, entries: entries)

        let agent = try FakeSSHAgent()
        agent.respondOnce(with: response)
        let keys = SSHAgentCommunicator(socketPath: agent.socketPath).getLoadedKeys()

        XCTAssertNil(keys)
    }

    func testKeyCountExceedingAvailablePayloadReturnsNilNotCrash() throws {
        // Only one key's worth of data is present, but nKeys claims three.
        let blob = FakeAgentResponse.validBlob(type: "ssh-ed25519")
        let entries = FakeAgentResponse.lengthPrefixed(blob) + FakeAgentResponse.lengthPrefixed("user@host")
        let response = FakeAgentResponse.identitiesAnswer(nKeys: 3, entries: entries)

        let agent = try FakeSSHAgent()
        agent.respondOnce(with: response)
        let keys = SSHAgentCommunicator(socketPath: agent.socketPath).getLoadedKeys()

        XCTAssertNil(keys)
    }
}

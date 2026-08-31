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

import Darwin
import XCTest
@testable import supreSSHion

/// Verifies removeKeys(blobs:) actually reuses one connection for a batch,
/// rather than just trusting the withConnection refactor by inspection.
final class SSHAgentCommunicatorBatchRemovalTests: XCTestCase {
    func testEmptyBlobsSucceedsWithoutConnecting() {
        // No FakeSSHAgent at all - if this didn't short-circuit before
        // attempting to connect, it would fail with .connectFailed against
        // a socket path nothing is listening on.
        let result = SSHAgentCommunicator(socketPath: "/tmp/supresshion-test-nonexistent-\(UUID().uuidString).sock")
            .removeKeys(blobs: [])

        if case .failure(let error) = result {
            XCTFail("expected success without connecting, got \(error)")
        }
    }

    func testBatchRemovalReusesOneConnectionForMultipleKeys() throws {
        let blobs = [Data([0x01, 0x02, 0x03]), Data([0x04, 0x05]), Data([0x06, 0x07, 0x08, 0x09])]
        let agent = try FakeSSHAgent()

        agent.handleOnce { fd in
            // One accepted connection answers all three REMOVE_IDENTITY
            // requests in sequence, each with SSH_AGENT_SUCCESS.
            for blob in blobs {
                let requestSize = FakeAgentResponse.removeIdentityRequestSize(forBlobSize: blob.count)
                var reqBuf = [UInt8](repeating: 0, count: requestSize)
                let n = recv(fd, &reqBuf, requestSize, Int32(MSG_WAITALL))
                guard n == requestSize else { return }

                let response = FakeAgentResponse.successResponse()
                response.withUnsafeBytes { raw in _ = send(fd, raw.baseAddress, response.count, 0) }
            }
        }

        let result = SSHAgentCommunicator(socketPath: agent.socketPath).removeKeys(blobs: blobs)

        if case .failure(let error) = result {
            XCTFail("expected success, got \(error)")
        }
        XCTAssertEqual(agent.acceptCount, 1, "batch removal should share a single connection")
    }

    func testBatchRemovalReportsAFailureAmongOtherwiseSuccessfulRemovals() throws {
        let blobs = [Data([0x01]), Data([0x02]), Data([0x03])]
        let agent = try FakeSSHAgent()

        agent.handleOnce { fd in
            for (index, blob) in blobs.enumerated() {
                let requestSize = FakeAgentResponse.removeIdentityRequestSize(forBlobSize: blob.count)
                var reqBuf = [UInt8](repeating: 0, count: requestSize)
                let n = recv(fd, &reqBuf, requestSize, Int32(MSG_WAITALL))
                guard n == requestSize else { return }

                // The middle removal is refused; the others succeed.
                let response = index == 1
                    ? FakeAgentResponse.bigEndianBytes(1) + Data([0xFF])
                    : FakeAgentResponse.successResponse()
                response.withUnsafeBytes { raw in _ = send(fd, raw.baseAddress, response.count, 0) }
            }
        }

        let result = SSHAgentCommunicator(socketPath: agent.socketPath).removeKeys(blobs: blobs)

        guard case .failure(.agentRefused) = result else {
            XCTFail("expected .agentRefused, got \(result)")
            return
        }
        XCTAssertEqual(agent.acceptCount, 1, "a mid-batch failure should not cause a reconnect")
    }
}

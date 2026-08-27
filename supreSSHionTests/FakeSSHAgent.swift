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
import Foundation

/// A minimal fake ssh-agent: listens on a Unix domain socket at a temp path
/// and replies with exactly the bytes handed to `respondOnce(with:)`. Lets
/// tests feed SSHAgentCommunicator crafted - including deliberately
/// malformed - wire responses without a real ssh-agent.
///
/// `SSHAgentCommunicator`'s calls are blocking, so the accept/respond work
/// happens on a background queue: bind+listen complete synchronously in
/// init() (so the socket exists and is already listening before any test
/// calls out to it), and respondOnce() dispatches the accept, which blocks
/// until the test's synchronous client call connects - no sleeps or polling
/// needed on either side.
final class FakeSSHAgent {
    enum SetupError: Error {
        case socketCreationFailed
        case bindFailed
        case listenFailed
    }

    let socketPath: String
    private let listenFD: Int32

    init() throws {
        socketPath = NSTemporaryDirectory() + "fake-agent-\(UUID().uuidString).sock"

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SetupError.socketCreationFailed }

        // Captured into locals rather than read as `self.socketPath` below:
        // referencing a stored property from inside a closure here would
        // implicitly capture `self`, which isn't fully initialized yet
        // (listenFD is still unset at this point in init).
        let path = socketPath
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            path.withCString { strncpy(rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self), $0, pathCapacity) }
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size - MemoryLayout.size(ofValue: addr.sun_path) + path.utf8.count)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { close(fd); throw SetupError.bindFailed }
        guard listen(fd, 1) == 0 else { close(fd); throw SetupError.listenFailed }

        listenFD = fd
    }

    /// Accepts exactly one connection on a background queue, drains
    /// whatever the client sends as its request, writes `response`, and
    /// closes. Returns immediately - call this before making the blocking
    /// client call on the calling thread.
    func respondOnce(with response: Data) {
        let fd = listenFD
        DispatchQueue.global(qos: .userInitiated).async {
            let clientFD = accept(fd, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }

            var reqBuf = [UInt8](repeating: 0, count: 5)
            _ = recv(clientFD, &reqBuf, reqBuf.count, 0)

            response.withUnsafeBytes { raw in
                _ = send(clientFD, raw.baseAddress, response.count, 0)
            }
        }
    }

    deinit {
        close(listenFD)
        unlink(socketPath)
    }
}

/// Builders for crafting SSH agent-protocol wire responses byte by byte,
/// including deliberately malformed ones.
enum FakeAgentResponse {
    static let identitiesAnswerType: UInt8 = 0x0c

    /// Exposed (not private) so tests can build deliberately-wrong length
    /// fields directly, rather than only well-formed ones via
    /// lengthPrefixed(_:).
    static func bigEndianBytes(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    /// A `string` field per the SSH agent wire format: a 4-byte big-endian
    /// length followed by that many bytes.
    static func lengthPrefixed(_ bytes: Data) -> Data {
        bigEndianBytes(UInt32(bytes.count)) + bytes
    }

    static func lengthPrefixed(_ string: String) -> Data {
        lengthPrefixed(Data(string.utf8))
    }

    /// A well-formed SSH public-key blob: `string algorithm-name` followed
    /// by arbitrary algorithm-specific key material.
    static func validBlob(type: String, keyMaterial: Data = Data([0xAA, 0xBB, 0xCC, 0xDD])) -> Data {
        lengthPrefixed(type) + keyMaterial
    }

    /// A full SSH_AGENT_IDENTITIES_ANSWER message: [4-byte msgLen][1-byte
    /// type][4-byte nKeys][entries]. msgLen is derived from `entries` unless
    /// `overrideMsgLen` is given, to let tests declare a size that
    /// disagrees with what's actually sent.
    static func identitiesAnswer(nKeys: UInt32, entries: Data, overrideMsgLen: UInt32? = nil) -> Data {
        let msgLen = overrideMsgLen ?? UInt32(1 + 4 + entries.count)
        return bigEndianBytes(msgLen) + Data([identitiesAnswerType]) + bigEndianBytes(nKeys) + entries
    }
}

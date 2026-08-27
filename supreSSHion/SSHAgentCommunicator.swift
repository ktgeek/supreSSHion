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
import Darwin
import Foundation

// A bounds-checked reader over a Data buffer of unknown (agent-controlled)
// structure. Every read returns nil instead of trapping when the buffer
// doesn't hold enough bytes, so a malformed or hostile ssh-agent response
// can only fail parsing - it can never crash the process. Tracks offsets
// relative to the buffer's own startIndex/endIndex rather than assuming a
// 0-based Data, since a sub-slice (e.g. a single key's blob, parsed again
// for its embedded type string) keeps its parent's indices.
private struct PayloadCursor {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    private var remaining: Int { data.endIndex - offset }

    mutating func readUInt32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        let value = UInt32(bigEndian: data[offset..<offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        offset += 4
        return value
    }

    mutating func readBytes(_ count: Int) -> Data? {
        guard count >= 0, remaining >= count else { return nil }
        let slice = data[offset..<offset + count]
        offset += count
        return slice
    }

    // SSH agent wire format's recurring `string` type: a 4-byte big-endian
    // length followed by that many bytes.
    mutating func readLengthPrefixedBytes() -> Data? {
        guard let length = readUInt32() else { return nil }
        return readBytes(Int(length))
    }
}

class SSHAgentCommunicator {
    private static let SSH_AGENT_SUCCESS: UInt8 = 0x06
    private static let SSH_AGENT_IDENTITIES_ANSWER: UInt8 = 0x0c
    private static let SSH_AGENTC_REQUEST_IDENTITIES: UInt8 = 0x0b
    private static let SSH_AGENTC_REMOVE_IDENTITY: UInt8 = 0x12
    private static let SSH_AGENTC_REMOVE_ALL_IDENTITIES: UInt8 = 0x13

    // A wedged ssh-agent must not be able to hang callers indefinitely -
    // notably the app-termination path, which runs under a limited budget.
    private static let socketTimeout = timeval(tv_sec: 2, tv_usec: 0)

    // Real ssh-agent implementations reply with far less than this. A
    // declared size above it is treated as malformed rather than trusted
    // enough to allocate - an attacker-controlled msgLen must not be able
    // to drive an unbounded Data(count:) allocation.
    private static let maxMessageSize: UInt32 = 256 * 1024

    private let socketPath: String

    init() {
        socketPath = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] ?? ""
    }

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    private func openSocket() throws -> Int32 {
        guard !socketPath.isEmpty else { throw AgentError.noAuthSock }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            socketPath.withCString { strncpy(rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self), $0, pathCapacity) }
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size - MemoryLayout.size(ofValue: addr.sun_path) + socketPath.utf8.count)

        let fd = socket(PF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentError.connectFailed(errno: errno) }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let connectErrno = errno
            Darwin.close(fd)
            throw AgentError.connectFailed(errno: connectErrno)
        }

        var timeout = SSHAgentCommunicator.socketTimeout
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        return fd
    }

    private func sendCommand(_ cmd: UInt8, to fd: Int32) {
        var buf = Data(count: 5)
        withUnsafeBytes(of: UInt32(1).bigEndian) { buf.replaceSubrange(0..<4, with: $0) }
        buf[4] = cmd
        _ = buf.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!, 5, 0) }
    }

    // Timeout is detected via errno after a short/failed recv: SO_RCVTIMEO
    // causes recv() to return -1/EAGAIN rather than a partial count. Any
    // other short read (including a clean EOF) is treated as a malformed
    // response rather than a timeout.
    private func recvAll(_ fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        let n = data.withUnsafeMutableBytes {
            Darwin.recv(fd, $0.baseAddress!, count, Int32(MSG_WAITALL))
        }
        guard n == count else {
            if n < 0, errno == EAGAIN || errno == EWOULDBLOCK { throw AgentError.timeout }
            throw AgentError.malformedResponse
        }
        return data
    }

    // Runs a throwing body that only ever throws AgentError, converting the
    // outcome to a Result at the public API boundary. Keeps the call sites
    // below written as plain `try`/`guard` rather than nested Result
    // switches.
    private func run<T>(_ body: () throws -> T) -> Result<T, AgentError> {
        do {
            return .success(try body())
        } catch let error as AgentError {
            return .failure(error)
        } catch {
            return .failure(.malformedResponse)
        }
    }

    @discardableResult
    func removeKeys() -> Result<Void, AgentError> {
        run {
            let fd = try openSocket()
            defer { Darwin.close(fd) }
            sendCommand(SSHAgentCommunicator.SSH_AGENTC_REMOVE_ALL_IDENTITIES, to: fd)
            let resp = try recvAll(fd, count: 5)
            let len = UInt32(bigEndian: resp.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            guard len == 1, resp[4] == SSHAgentCommunicator.SSH_AGENT_SUCCESS else {
                NSLog("Failure removing keys from agent")
                throw AgentError.agentRefused
            }
            NSLog("Successfully removed keys")
        }
    }

    @discardableResult
    func removeKey(blob: Data) -> Result<Void, AgentError> {
        run {
            let fd = try openSocket()
            defer { Darwin.close(fd) }
            let payloadLen = 1 + 4 + blob.count
            var buf = Data(count: 4 + payloadLen)
            withUnsafeBytes(of: UInt32(payloadLen).bigEndian) { buf.replaceSubrange(0..<4, with: $0) }
            buf[4] = SSHAgentCommunicator.SSH_AGENTC_REMOVE_IDENTITY
            withUnsafeBytes(of: UInt32(blob.count).bigEndian) { buf.replaceSubrange(5..<9, with: $0) }
            buf.replaceSubrange(9..<9+blob.count, with: blob)
            _ = buf.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!, 4 + payloadLen, 0) }
            let resp = try recvAll(fd, count: 5)
            let len = UInt32(bigEndian: resp.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            guard len == 1, resp[4] == SSHAgentCommunicator.SSH_AGENT_SUCCESS else {
                NSLog("Failure removing key from agent")
                throw AgentError.agentRefused
            }
            NSLog("Successfully removed key")
        }
    }

    func getLoadedKeys() -> Result<[SSHKey], AgentError> {
        run {
            let fd = try openSocket()
            defer { Darwin.close(fd) }
            sendCommand(SSHAgentCommunicator.SSH_AGENTC_REQUEST_IDENTITIES, to: fd)

            let header = try recvAll(fd, count: 5)
            let msgLen = UInt32(bigEndian: header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            guard header[4] == SSHAgentCommunicator.SSH_AGENT_IDENTITIES_ANSWER else {
                NSLog("Failure getting list of keys")
                throw AgentError.malformedResponse
            }
            // msgLen must at minimum cover the 1-byte type (already consumed
            // above) and the 4-byte key count read next; anything smaller is
            // malformed. The upper bound rejects an implausible size before
            // it can drive an unbounded allocation below.
            guard msgLen >= 5, msgLen <= SSHAgentCommunicator.maxMessageSize else {
                NSLog("Rejecting identities response of implausible size (\(msgLen) bytes)")
                throw AgentError.malformedResponse
            }

            let nKeysBuf = try recvAll(fd, count: 4)
            let nKeys = UInt32(bigEndian: nKeysBuf.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })

            let payloadLen = Int(msgLen) - 5
            guard payloadLen > 0 else { return [] }
            let payload = try recvAll(fd, count: payloadLen)

            var cursor = PayloadCursor(payload)
            var keys = [SSHKey]()

            for _ in 0..<nKeys {
                guard let blob = cursor.readLengthPrefixedBytes() else {
                    NSLog("Malformed identities response from agent (truncated key blob)")
                    throw AgentError.malformedResponse
                }
                guard let comment = cursor.readLengthPrefixedBytes() else {
                    NSLog("Malformed identities response from agent (truncated comment)")
                    throw AgentError.malformedResponse
                }

                let digest = SHA256.hash(data: blob)
                let b64 = Data(digest).base64EncodedString()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "="))
                let fingerprint = "SHA256:" + b64

                // The human-readable key type (e.g. "ssh-ed25519") is itself
                // the leading length-prefixed string inside the blob - SSH
                // public-key blobs are `string algorithm-name` followed by
                // algorithm-specific data, not a separate wire field.
                // Parsing it through its own cursor keeps a bogus embedded
                // length from reading past this blob's own bounds into
                // whatever follows in payload; a length that doesn't fit is
                // the same kind of malformed input as a truncated blob or
                // comment above, so it's treated the same way.
                var blobCursor = PayloadCursor(blob)
                guard let typeBytes = blobCursor.readLengthPrefixedBytes() else {
                    NSLog("Malformed identities response from agent (invalid key type length)")
                    throw AgentError.malformedResponse
                }
                // A non-UTF8 type string is tolerated as empty for now -
                // decode failures are a separate, lower-severity concern
                // from bounds safety.
                let keyType = String(bytes: typeBytes, encoding: .utf8) ?? ""
                let commentString = String(bytes: comment, encoding: .utf8) ?? ""

                keys.append(SSHKey(type: keyType, fingerprint: fingerprint, comment: commentString, keyBlob: Data(blob)))
            }
            return keys
        }
    }
}

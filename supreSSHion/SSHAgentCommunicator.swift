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

private let SSH_AGENT_SUCCESS: UInt8 = 0x06
private let SSH_AGENT_IDENTITIES_ANSWER: UInt8 = 0x0c
private let SSH_AGENTC_REQUEST_IDENTITIES: UInt8 = 0x0b
private let SSH_AGENTC_REMOVE_ALL_IDENTITIES: UInt8 = 0x13

class SSHAgentCommunicator {
    private let socketPath: String

    init() {
        socketPath = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] ?? ""
    }

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    private func openSocket() -> Int32? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            socketPath.withCString { strncpy(rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self), $0, pathCapacity) }
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size - MemoryLayout.size(ofValue: addr.sun_path) + socketPath.utf8.count)

        let fd = socket(PF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { Darwin.close(fd); return nil }
        return fd
    }

    private func sendCommand(_ cmd: UInt8, to fd: Int32) {
        var buf = Data(count: 5)
        withUnsafeBytes(of: UInt32(1).bigEndian) { buf.replaceSubrange(0..<4, with: $0) }
        buf[4] = cmd
        _ = buf.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!, 5, 0) }
    }

    private func recvAll(_ fd: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        let n = data.withUnsafeMutableBytes {
            Darwin.recv(fd, $0.baseAddress!, count, Int32(MSG_WAITALL))
        }
        return n == count ? data : nil
    }

    func removeKeys() {
        guard let fd = openSocket() else { return }
        defer { Darwin.close(fd) }
        sendCommand(SSH_AGENTC_REMOVE_ALL_IDENTITIES, to: fd)
        guard let resp = recvAll(fd, count: 5) else { return }
        let len = UInt32(bigEndian: resp.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        if len == 1 && resp[4] == SSH_AGENT_SUCCESS {
            NSLog("Successfully removed keys")
        } else {
            NSLog("Failure removing keys from agent")
        }
    }

    func getLoadedKeys() -> [[String: String]]? {
        guard let fd = openSocket() else { return nil }
        defer { Darwin.close(fd) }
        sendCommand(SSH_AGENTC_REQUEST_IDENTITIES, to: fd)

        guard let header = recvAll(fd, count: 5) else { return nil }
        let msgLen = UInt32(bigEndian: header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard header[4] == SSH_AGENT_IDENTITIES_ANSWER else {
            NSLog("Failure getting list of keys")
            return nil
        }

        guard let nKeysBuf = recvAll(fd, count: 4) else { return nil }
        let nKeys = UInt32(bigEndian: nKeysBuf.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })

        let payloadLen = Int(msgLen) - 5
        guard payloadLen > 0 else { return [] }
        guard let payload = recvAll(fd, count: payloadLen) else { return nil }

        var keys = [[String: String]]()
        var offset = 0

        for _ in 0..<nKeys {
            guard offset + 4 <= payloadLen else { break }
            let blobLen = Int(UInt32(bigEndian: payload[offset..<offset+4]
                .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            offset += 4
            guard offset + blobLen <= payloadLen else { break }

            // SHA-256 fingerprint of the raw key blob
            let blob = payload[offset..<offset + blobLen]
            let digest = SHA256.hash(data: blob)
            let b64 = Data(digest).base64EncodedString()
                .trimmingCharacters(in: CharacterSet(charactersIn: "="))
            let fingerprint = "SHA256:" + b64

            // Key type: first length-prefixed string inside the blob
            let typeLen = Int(UInt32(bigEndian: payload[offset..<offset+4]
                .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            let keyType = typeLen > 0 ? String(bytes: payload[offset+4..<offset+4+typeLen], encoding: .utf8) ?? "" : ""
            offset += blobLen

            // Comment
            guard offset + 4 <= payloadLen else { break }
            let commentLen = Int(UInt32(bigEndian: payload[offset..<offset+4]
                .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            offset += 4
            guard offset + commentLen <= payloadLen else { break }
            let comment = String(bytes: payload[offset..<offset+commentLen], encoding: .utf8) ?? ""
            offset += commentLen

            keys.append(["type": keyType, "fingerprint": fingerprint, "comment": comment])
        }
        return keys
    }
}

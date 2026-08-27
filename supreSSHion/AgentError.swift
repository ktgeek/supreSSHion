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

/// The ways SSHAgentCommunicator can fail to complete a request. Every
/// public method reports one of these via Result rather than silently
/// mapping every failure to nil/Void, so callers can eventually distinguish
/// "the agent has no keys" from "the agent could not be reached" or "the
/// agent sent something we can't parse."
enum AgentError: Error, Equatable {
    case noAuthSock
    case connectFailed(errno: Int32)
    case timeout
    case malformedResponse
    case agentRefused
}

extension AgentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noAuthSock:
            return "SSH_AUTH_SOCK is not set"
        case .connectFailed(let errno):
            return "Could not connect to ssh-agent (\(String(cString: strerror(errno))))"
        case .timeout:
            return "ssh-agent did not respond in time"
        case .malformedResponse:
            return "ssh-agent sent a malformed response"
        case .agentRefused:
            return "ssh-agent refused the request"
        }
    }
}

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

import AppKit
import UserNotifications

/// Presents a failed key removal to the user through whichever channel fits
/// how it happened:
///
/// - A removal the user just triggered (menu's "Remove All Keys", the Keys
///   window's buttons) gets a blocking NSAlert - the user is right there.
/// - A removal that ran in the background (screen lock, disable-timer
///   expiry) gets a system notification, since there's no window to alert.
/// - A removal that ran during app termination gets neither - there's no
///   time budget left to show anything before the process exits - so a
///   marker file is left instead, and surfaced as a notification the next
///   time the app launches.
enum NotificationPresenter {
    private static let quitFailureFlagURL = ExemptionStore.defaultFileURL
        .deletingLastPathComponent()
        .appendingPathComponent("last-quit-removal-failed")

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                NSLog("Notification authorization request failed: \(error.localizedDescription)")
            } else if !granted {
                NSLog("Notification authorization was not granted")
            }
        }
    }

    static func presentUserInitiatedFailure(_ error: AgentError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could Not Remove Keys"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    static func notifyAutomaticFailure(reason: String, error: AgentError) {
        post(title: "supreSSHion Could Not Remove Keys",
             body: "After \(reason), ssh-agent keys could not be removed: \(error.localizedDescription)")
    }

    /// Call from removeKeysOnTermination() - there's no time budget left to
    /// show a notification during app termination, so this only leaves a
    /// marker for the next launch to find.
    static func recordTerminationFailure() {
        let directory = quitFailureFlagURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: quitFailureFlagURL.path, contents: nil)
    }

    /// Call once at launch. If recordTerminationFailure() left a marker,
    /// surfaces it as a notification and removes the marker, so it's
    /// reported exactly once.
    static func surfacePendingTerminationFailure() {
        guard FileManager.default.fileExists(atPath: quitFailureFlagURL.path) else { return }
        try? FileManager.default.removeItem(at: quitFailureFlagURL)
        post(title: "supreSSHion Could Not Remove Keys",
             body: "The last time supreSSHion quit, it could not confirm all keys were removed from ssh-agent.")
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}

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
import Observation

@Observable
final class ExemptionStore {
    private struct ExemptionFile: Codable {
        var version: Int
        var exemptions: [KeyExemption]
    }

    static var defaultFileURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("supreSSHion", isDirectory: true)
            .appendingPathComponent("exemptions.plist")
    }

    private let fileURL: URL

    private(set) var exemptions: [KeyExemption] = []
    private(set) var fingerprints: Set<String> = []

    init(fileURL: URL = ExemptionStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    func isExempt(fingerprint: String) -> Bool {
        fingerprints.contains(fingerprint)
    }

    @discardableResult
    func exempt(fingerprint: String, label: String) -> Bool {
        guard !fingerprints.contains(fingerprint) else { return false }
        exemptions.append(KeyExemption(fingerprint: fingerprint, label: label))
        sortAndReindex()
        save()
        return true
    }

    func unexempt(fingerprint: String) {
        guard fingerprints.contains(fingerprint) else { return }
        exemptions.removeAll { $0.fingerprint == fingerprint }
        sortAndReindex()
        save()
    }

    // Removes several exemptions with a single save(), rather than the
    // caller looping unexempt(fingerprint:) and writing the whole plist
    // once per removal.
    func unexempt(fingerprints toRemove: Set<String>) {
        let matching = toRemove.intersection(fingerprints)
        guard !matching.isEmpty else { return }
        exemptions.removeAll { matching.contains($0.fingerprint) }
        sortAndReindex()
        save()
    }

    func setLabel(_ label: String, for fingerprint: String) {
        guard let index = exemptions.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
        exemptions[index].label = label
        sortAndReindex()
        save()
    }

    static func normalize(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("sha256:") {
            value = String(value.dropFirst("sha256:".count))
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "="))

        let paddingNeeded = (4 - value.count % 4) % 4
        let padded = value + String(repeating: "=", count: paddingNeeded)

        guard let data = Data(base64Encoded: padded), data.count == 32 else { return nil }

        let unpadded = data.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:" + unpadded
    }

    private func sortAndReindex() {
        exemptions.sort { lhs, rhs in
            if lhs.label != rhs.label { return lhs.label < rhs.label }
            return lhs.fingerprint < rhs.fingerprint
        }
        fingerprints = Set(exemptions.map { $0.fingerprint })
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let file = try PropertyListDecoder().decode(ExemptionFile.self, from: data)
            exemptions = file.exemptions
            sortAndReindex()
        } catch {
            NSLog("Failed to decode exemptions plist at \(fileURL.path): \(error)")
        }
    }

    private func save() {
        let file = ExemptionFile(version: 1, exemptions: exemptions)
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(file)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save exemptions plist at \(fileURL.path): \(error)")
        }
    }
}

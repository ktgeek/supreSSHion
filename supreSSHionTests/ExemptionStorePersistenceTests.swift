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

final class ExemptionStorePersistenceTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExemptionStorePersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("exemptions.plist")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private let fingerprintA = "SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU"
    private let fingerprintB = "SHA256:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ"

    // MARK: - Round trip

    func testExemptPersistsAcrossInstances() {
        let store1 = ExemptionStore(fileURL: fileURL)
        XCTAssertTrue(store1.exempt(fingerprint: fingerprintA, label: "work laptop"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let store2 = ExemptionStore(fileURL: fileURL)
        XCTAssertTrue(store2.isExempt(fingerprint: fingerprintA))
        XCTAssertEqual(store2.exemptions.first?.label, "work laptop")
    }

    func testUnexemptPersistsAcrossInstances() {
        let store1 = ExemptionStore(fileURL: fileURL)
        store1.exempt(fingerprint: fingerprintA, label: "a")
        store1.exempt(fingerprint: fingerprintB, label: "b")
        store1.unexempt(fingerprint: fingerprintA)

        let store2 = ExemptionStore(fileURL: fileURL)
        XCTAssertFalse(store2.isExempt(fingerprint: fingerprintA))
        XCTAssertTrue(store2.isExempt(fingerprint: fingerprintB))
    }

    func testBatchUnexemptRemovesOnlyMatchingFingerprints() {
        let store = ExemptionStore(fileURL: fileURL)
        let fingerprintC = "SHA256:AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKK"
        store.exempt(fingerprint: fingerprintA, label: "a")
        store.exempt(fingerprint: fingerprintB, label: "b")
        store.exempt(fingerprint: fingerprintC, label: "c")

        // Includes one fingerprint the store doesn't know about - must not
        // affect the others.
        store.unexempt(fingerprints: [fingerprintA, fingerprintC, "SHA256:unknown"])

        XCTAssertFalse(store.isExempt(fingerprint: fingerprintA))
        XCTAssertTrue(store.isExempt(fingerprint: fingerprintB))
        XCTAssertFalse(store.isExempt(fingerprint: fingerprintC))
        XCTAssertEqual(store.exemptions.count, 1)
    }

    func testBatchUnexemptWithNoMatchesIsANoOpAndDoesNotWrite() {
        let store = ExemptionStore(fileURL: fileURL)
        store.exempt(fingerprint: fingerprintA, label: "a")

        store.unexempt(fingerprints: ["SHA256:unknown1", "SHA256:unknown2"])

        XCTAssertTrue(store.isExempt(fingerprint: fingerprintA))
        XCTAssertEqual(store.exemptions.count, 1)
    }

    func testSetLabelPersistsAcrossInstances() {
        let store1 = ExemptionStore(fileURL: fileURL)
        store1.exempt(fingerprint: fingerprintA, label: "old label")
        store1.setLabel("new label", for: fingerprintA)

        let store2 = ExemptionStore(fileURL: fileURL)
        XCTAssertEqual(store2.exemptions.first?.label, "new label")
    }

    // MARK: - No file yet

    func testMissingFileLoadsEmpty() {
        let store = ExemptionStore(fileURL: fileURL)
        XCTAssertTrue(store.exemptions.isEmpty)
        XCTAssertTrue(store.fingerprints.isEmpty)
    }

    // MARK: - Duplicate / no-op mutation behavior

    func testExemptingTwiceIsANoOp() {
        let store = ExemptionStore(fileURL: fileURL)
        XCTAssertTrue(store.exempt(fingerprint: fingerprintA, label: "first"))
        XCTAssertFalse(store.exempt(fingerprint: fingerprintA, label: "second"))
        XCTAssertEqual(store.exemptions.count, 1)
        XCTAssertEqual(store.exemptions.first?.label, "first")
    }

    func testUnexemptingUnknownFingerprintIsANoOp() {
        let store = ExemptionStore(fileURL: fileURL)
        store.unexempt(fingerprint: fingerprintA)
        XCTAssertTrue(store.exemptions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Corrupt file: loads empty, and does not overwrite until a real mutation

    func testCorruptFileLoadsEmptyWithoutOverwriting() throws {
        let garbage = Data("this is not a plist".utf8)
        try garbage.write(to: fileURL)

        let store = ExemptionStore(fileURL: fileURL)
        XCTAssertTrue(store.exemptions.isEmpty)

        // The corrupt file must be left untouched by merely loading it.
        let onDiskAfterLoad = try Data(contentsOf: fileURL)
        XCTAssertEqual(onDiskAfterLoad, garbage)

        // Only a real mutation should replace the corrupt file with valid content.
        store.exempt(fingerprint: fingerprintA, label: "recovered")
        let onDiskAfterMutation = try Data(contentsOf: fileURL)
        XCTAssertNotEqual(onDiskAfterMutation, garbage)

        let reloaded = ExemptionStore(fileURL: fileURL)
        XCTAssertTrue(reloaded.isExempt(fingerprint: fingerprintA))
    }
}

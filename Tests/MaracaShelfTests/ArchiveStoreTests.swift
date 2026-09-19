import XCTest
@testable import MaracaShelf

final class ArchiveStoreTests: XCTestCase {
    private var directory: URL!
    private var root: URL!
    private var store: ArchiveStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("MaracaArchiveTests-" + UUID().uuidString)
        root = directory.appendingPathComponent("Archive")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ArchiveStore(root: root)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testLegacyEntryShowsContentAndStillDeduplicates() throws {
        let folder = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let content = folder.appendingPathComponent(".env")
        try "original".write(to: content, atomically: true, encoding: .utf8)
        try "url:/original".write(to: folder.appendingPathComponent(".maraca-source-key"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.entries().map { $0.resolvingSymlinksInPath() }, [content.resolvingSymlinksInPath()])
        let replacement = directory.appendingPathComponent("replacement.txt")
        try "replacement".write(to: replacement, atomically: true, encoding: .utf8)
        try store.archive(replacement, sourceKey: "url:/original")
        XCTAssertEqual(store.entries().map { $0.resolvingSymlinksInPath() }, [content.resolvingSymlinksInPath()])
        XCTAssertEqual(try String(contentsOf: content), "original")
    }

    func testHiddenFilesAndMetadataNamedContentSurvive() throws {
        for name in [".env", ".gitignore", ".maraca-source-key"] {
            let source = directory.appendingPathComponent(name)
            try name.write(to: source, atomically: true, encoding: .utf8)
            try store.archive(source, sourceKey: nil)
        }
        XCTAssertEqual(Set(store.entries().map(\.lastPathComponent)), [".env", ".gitignore", ".maraca-source-key"])
        for entry in store.entries() {
            XCTAssertEqual(try String(contentsOf: entry), entry.lastPathComponent)
        }
    }

    func testConcurrentSessionsDeduplicateAtomically() throws {
        let source = directory.appendingPathComponent("file.txt")
        try "payload".write(to: source, atomically: true, encoding: .utf8)
        DispatchQueue.concurrentPerform(iterations: 30) { _ in
            do { try store.archive(source, sourceKey: "same-source") }
            catch { XCTFail("Concurrent archive failed: \(error)") }
        }
        XCTAssertEqual(store.entries().count, 1)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(store.entries().first)), "payload")
    }

    func testFailedCopyDoesNotPublishAnEntryOrLeaveMetadata() throws {
        XCTAssertThrowsError(try store.archive(directory.appendingPathComponent("missing"), sourceKey: "missing"))
        XCTAssertTrue(store.entries().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testRemoveClearAndExpiryKeepMetadataConsistent() throws {
        let source = directory.appendingPathComponent("file.txt")
        try "payload".write(to: source, atomically: true, encoding: .utf8)
        try store.archive(source, sourceKey: "source")
        try store.remove(XCTUnwrap(store.entries().first))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        try store.archive(source, sourceKey: "source")
        XCTAssertTrue(store.purgeExpired(before: Date().addingTimeInterval(60)))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        try store.archive(source, sourceKey: "source")
        try store.clearAll()
        XCTAssertTrue(store.entries().isEmpty)
        try store.archive(source, sourceKey: "source")
        XCTAssertEqual(store.entries().count, 1)
    }

    func testCloseWaitsForDelayedPromiseAndArchiveCompletion() throws {
        let lifetime = ImportLifetime()
        let session = directory.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let file = session.appendingPathComponent("promised.txt")
        XCTAssertTrue(lifetime.begin())
        let cleaned = expectation(description: "Session cleaned after archival")
        lifetime.close {
            XCTAssertEqual(self.store.entries().count, 1)
            try? FileManager.default.removeItem(at: session)
            cleaned.fulfill()
        }
        XCTAssertFalse(lifetime.begin(), "A closed shelf must not accept another import")
        // The sender finishes delivering its file only after the shelf window has closed.
        try "promised payload".write(to: file, atomically: true, encoding: .utf8)
        try store.archive(file, sourceKey: "promise")
        lifetime.finish()
        wait(for: [cleaned], timeout: 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.path))
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(store.entries().first)), "promised payload")
    }

    func testFailedImportAndRepeatedCloseCleanUpOnce() {
        let lifetime = ImportLifetime()
        XCTAssertTrue(lifetime.begin())
        let cleaned = expectation(description: "Cleanup")
        cleaned.assertForOverFulfill = true
        lifetime.close { cleaned.fulfill() }
        lifetime.close { XCTFail("Duplicate cleanup") }
        lifetime.finish() // An error callback must release its ticket too.
        wait(for: [cleaned], timeout: 3)
    }
}

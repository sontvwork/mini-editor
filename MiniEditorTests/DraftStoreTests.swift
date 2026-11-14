import XCTest
@testable import MiniEditor

final class DraftStoreTests: XCTestCase {
    func testNextTitleUsesSmallestUnusedNumber() {
        XCTAssertEqual(DraftStore.nextTitle(existing: []), "Chưa đặt tên-1")
        XCTAssertEqual(DraftStore.nextTitle(existing: ["Chưa đặt tên-1", "Chưa đặt tên-3"]), "Chưa đặt tên-2")
        XCTAssertEqual(DraftStore.nextTitle(existing: ["Chưa đặt tên-2", "Ghi chú"]), "Chưa đặt tên-1")
    }

    func testCreateWriteReadDelete() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        let store = DraftStore(directory: dir.url.appendingPathComponent("drafts"))
        let id = UUID()
        try store.create(id)
        XCTAssertTrue(store.exists(id))
        XCTAssertEqual(store.url(for: id).lastPathComponent, "\(id.uuidString).txt")
        try store.write("# Prompt\n", id: id)
        XCTAssertEqual(try store.read(id), "# Prompt\n")
        try store.delete(id)
        XCTAssertFalse(store.exists(id))
    }

    func testLanguageDetection() {
        XCTAssertEqual(Language.detect(fileName: "a.sh", firstLine: ""), .bash)
        XCTAssertEqual(Language.detect(fileName: "a.command", firstLine: ""), .bash)
        XCTAssertEqual(Language.detect(fileName: "README.markdown", firstLine: ""), .markdown)
        XCTAssertEqual(Language.detect(fileName: "deploy", firstLine: "#!/usr/bin/env bash"), .bash)
        XCTAssertEqual(Language.detect(fileName: "deploy", firstLine: "#!/bin/zsh -e"), .bash)
        XCTAssertEqual(Language.detect(fileName: "x.py", firstLine: "#!/usr/bin/env python3"), .plain)
        XCTAssertEqual(Language.detect(fileName: "x", firstLine: "#!/usr/bin/fish"), .plain)
        XCTAssertEqual(Language.detectDraft(firstLine: "hello"), .markdown)
        XCTAssertEqual(Language.detectDraft(firstLine: "#!/bin/sh"), .bash)
    }
}

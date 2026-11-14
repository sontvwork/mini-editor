import XCTest
@testable import MiniEditor

final class FileNodeTests: XCTestCase {
    private var dir: TemporaryDirectory!

    override func setUpWithError() throws {
        dir = try TemporaryDirectory()
    }

    override func tearDown() {
        dir.remove()
    }

    func testHidesIgnoredNamesAndKeepsOtherDotfiles() throws {
        for name in [".git", "node_modules", "vendor", ".idea", ".vscode", "src"] {
            try dir.makeDirectory(name)
        }
        try dir.makeFile(".DS_Store")
        try dir.makeFile(".env")
        try dir.makeFile("deploy.sh")

        let names = DirectoryLister.entries(at: dir.url).map(\.name)
        XCTAssertEqual(names, ["src", ".env", "deploy.sh"])
    }

    func testDirectoriesFirstThenFinderOrdering() {
        let entries: [DirectoryLister.Entry] = [
            .init(name: "file10.sh", isDirectory: false),
            .init(name: "Beta", isDirectory: true),
            .init(name: "file2.sh", isDirectory: false),
            .init(name: "alpha", isDirectory: true),
            .init(name: "B.md", isDirectory: false),
            .init(name: "a.md", isDirectory: false),
        ]
        XCTAssertEqual(DirectoryLister.sorted(entries).map(\.name),
                       ["alpha", "Beta", "a.md", "B.md", "file2.sh", "file10.sh"])
    }

    func testSymlinkToDirectoryIsDirectory() throws {
        try dir.makeDirectory("real")
        try FileManager.default.createSymbolicLink(at: dir.url.appendingPathComponent("link"),
                                                   withDestinationURL: dir.url.appendingPathComponent("real"))
        let entries = DirectoryLister.entries(at: dir.url)
        XCTAssertEqual(entries, [.init(name: "link", isDirectory: true), .init(name: "real", isDirectory: true)])
    }

    func testIsHiddenRelativePath() {
        XCTAssertTrue(DirectoryLister.isHidden(relativePath: ".git/objects"))
        XCTAssertTrue(DirectoryLister.isHidden(relativePath: "web/node_modules/x"))
        XCTAssertFalse(DirectoryLister.isHidden(relativePath: "deploy/scripts"))
    }

    func testLazyLoadingAndRelativePaths() throws {
        try dir.makeFile("deploy/prod.sh")
        let root = FileNode.root(of: dir.url)
        XCTAssertFalse(root.isLoaded)

        let deploy = try XCTUnwrap(root.loadedChildren().first)
        XCTAssertEqual(deploy.relativePath, "deploy")
        XCTAssertFalse(deploy.isLoaded)
        XCTAssertEqual(deploy.loadedChildren().map(\.relativePath), ["deploy/prod.sh"])
        XCTAssertTrue(root.loadedDescendant(atRelativePath: "deploy/prod.sh") != nil)
    }

    func testReloadReusesExistingNodesAndPicksUpChanges() throws {
        try dir.makeFile("deploy/prod.sh")
        try dir.makeFile("old.sh")
        let root = FileNode.root(of: dir.url)
        let deploy = try XCTUnwrap(root.loadedChildren().first)
        _ = deploy.loadedChildren()

        try FileManager.default.removeItem(at: dir.url.appendingPathComponent("old.sh"))
        try dir.makeFile("new.sh")
        root.reloadChildren()

        XCTAssertEqual(root.loadedChildren().map(\.name), ["deploy", "new.sh"])
        XCTAssertTrue(root.loadedChildren().first === deploy)
        XCTAssertTrue(deploy.isLoaded) // con đã nạp vẫn còn
        XCTAssertEqual(root.loadedDirectories().map(\.relativePath), ["", "deploy"])
    }
}

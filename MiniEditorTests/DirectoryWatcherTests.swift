import XCTest
@testable import MiniEditor

@MainActor
final class DirectoryWatcherTests: XCTestCase {
    func testReportsRealPathOfChangedDirectoryOnce() async throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        try dir.makeDirectory("deploy")
        let realDeploy = DirectoryWatcher.realPath(dir.url.appendingPathComponent("deploy").path)

        let changed = expectation(description: "thay đổi được báo")
        var received: [DirectoryChanges] = []
        let watcher = DirectoryWatcher { changes in
            received.append(changes)
            if changes.paths.contains(realDeploy) || changes.recursivePaths.contains(realDeploy) {
                changed.fulfill()
            }
        }
        watcher.watch(paths: [dir.url.path])
        try await Task.sleep(for: .milliseconds(300)) // để stream khởi động

        // Nhiều thay đổi liên tiếp → gom thành một lần báo nhờ debounce.
        try dir.makeFile("deploy/a.sh")
        try dir.makeFile("deploy/b.sh")
        try dir.makeFile("deploy/c.sh")

        await fulfillment(of: [changed], timeout: 5)
        watcher.stop()
        // Lần báo cho thư mục gốc (do bước dựng test tạo `deploy`) có thể đến trễ; chỉ đếm `deploy`.
        let deployReports = received.filter { $0.paths.contains(realDeploy) || $0.recursivePaths.contains(realDeploy) }
        XCTAssertEqual(deployReports.count, 1, "\(received)")
    }

    func testRealPathResolvesSymlinks() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        // /var → /private/var trên macOS.
        XCTAssertTrue(DirectoryWatcher.realPath(dir.url.path).hasPrefix("/private/"))
    }
}

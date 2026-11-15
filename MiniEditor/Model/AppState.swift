import CryptoKit
import Foundation

/// Nguồn sự thật duy nhất cho UI.
@MainActor
final class AppState {
    private(set) var fontSize: CGFloat = FontSize.default
    private(set) var workspaces: [Workspace] = []
    private(set) var drafts: [DraftInfo] = []
    private(set) var layout = ColumnLayout.initial()
    /// Buffer của mọi tab đang mở.
    private(set) var buffers: [BufferID: Buffer] = [:]

    let draftStore: DraftStore
    let autosave: AutosaveService

    /// Gọi khi danh sách workspace thay đổi (thêm/gỡ). Đổi trạng thái mở/đóng thư mục không gọi.
    var onWorkspacesChange: (() -> Void)?
    /// Gọi khi danh sách nháp thay đổi (tạo, lưu thành file).
    var onDraftsChange: (() -> Void)?
    /// Gọi khi bố cục cột/tab hoặc cột đang focus thay đổi.
    var onLayoutChange: (() -> Void)?
    /// Gọi mỗi khi cỡ chữ thay đổi.
    var onFontSizeChange: ((CGFloat) -> Void)?
    /// Gọi khi trạng thái lưu của một buffer đổi.
    var onBufferStatusChange: ((Buffer) -> Void)?
    /// Gọi khi nội dung buffer được nạp lại từ đĩa (file bị sửa bên ngoài).
    var onBufferReload: ((Buffer) -> Void)?
    /// Gọi khi ngôn ngữ của một buffer đổi.
    var onBufferLanguageChange: ((Buffer) -> Void)?
    /// Có gì đó cần ghi vào session.json.
    var onSessionDirty: (() -> Void)?

    init(draftStore: DraftStore = DraftStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("MiniEditor-drafts-\(UUID().uuidString)", isDirectory: true))) {
        self.draftStore = draftStore
        autosave = AutosaveService(draftStore: draftStore)
        autosave.onStatusChange = { [weak self] buffer in
            self?.onBufferStatusChange?(buffer)
        }
        autosave.onReload = { [weak self] buffer in
            self?.onBufferReload?(buffer)
        }
    }

    func markSessionDirty() {
        onSessionDirty?()
    }

    // MARK: - Cỡ chữ

    func increaseFontSize() { setFontSize(FontSize.increased(fontSize)) }
    func decreaseFontSize() { setFontSize(FontSize.decreased(fontSize)) }
    func resetFontSize() { setFontSize(FontSize.default) }

    func setFontSize(_ size: CGFloat) {
        let newSize = FontSize.clamped(size)
        guard newSize != fontSize else { return }
        fontSize = newSize
        onFontSizeChange?(newSize)
        markSessionDirty()
    }

    // MARK: - Workspace

    func workspace(id: Workspace.ID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    /// Thêm workspace; thư mục đã có thì trả về workspace cũ.
    @discardableResult
    func addWorkspace(url: URL) -> Workspace.ID {
        let standardized = url.standardizedFileURL
        if let existing = workspaces.first(where: { $0.url.path == standardized.path }) {
            return existing.id
        }
        let workspace = Workspace(url: standardized)
        workspaces.append(workspace)
        onWorkspacesChange?()
        markSessionDirty()
        return workspace.id
    }

    /// Gỡ khỏi sidebar, không xoá gì trên đĩa.
    func removeWorkspace(id: Workspace.ID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces.remove(at: index)
        onWorkspacesChange?()
        setLayout(ColumnLayoutEngine.removeWorkspace(id, from: layout))
        markSessionDirty()
    }

    /// Workspace chứa file (workspace lồng nhau → chọn cái sâu nhất).
    func workspaceID(containing url: URL) -> Workspace.ID? {
        let path = url.standardizedFileURL.path
        return workspaces
            .filter { path.hasPrefix($0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/") }
            .max { $0.url.path.count < $1.url.path.count }?
            .id
    }

    func setDirectory(_ relativePath: String, expanded: Bool, in id: Workspace.ID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        if expanded {
            workspaces[index].expandedDirs.insert(relativePath)
        } else {
            workspaces[index].expandedDirs.remove(relativePath)
        }
        markSessionDirty()
    }

    func setWorkspace(_ id: Workspace.ID, collapsed: Bool) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].collapsed = collapsed
        markSessionDirty()
    }

    // MARK: - Tab & cột

    /// Mở file thành tab theo quy tắc SPEC §3.2. Đã mở thì chỉ focus tab đó.
    func openFile(_ url: URL) throws {
        let id = BufferID.file(path: url)
        if buffers[id] == nil {
            register(try Buffer.load(url: url))
        }
        open(Tab(buffer: id, workspaceID: workspaceID(containing: url)))
    }

    /// Đóng tab. Không bao giờ hỏi lưu: nội dung được lưu ngay trước khi đóng.
    /// Lưu lỗi (hoặc đang tạm dừng vì file đổi bên ngoài) → giữ tab lại, nội dung còn trong RAM.
    /// `discardingChanges`: đóng hẳn, bỏ thay đổi chưa lưu ([Đóng tab] trên banner file bị xoá).
    func closeTab(_ id: BufferID, discardingChanges: Bool = false) {
        if let buffer = buffers[id] {
            if discardingChanges {
                autosave.cancel(buffer)
            } else {
                autosave.save(buffer)
                if case .failed = buffer.saveState { return }
            }
        }
        setLayout(ColumnLayoutEngine.close(id, in: layout))
    }

    func closeActiveTab() {
        guard let tab = layout.focusedColumn.activeTab else { return }
        closeTab(tab.buffer)
    }

    func activateTab(_ id: BufferID) {
        setLayout(ColumnLayoutEngine.activate(id, in: layout))
    }

    func selectNextTab() {
        setLayout(ColumnLayoutEngine.selectAdjacentTab(offset: 1, in: layout))
    }

    func selectPreviousTab() {
        setLayout(ColumnLayoutEngine.selectAdjacentTab(offset: -1, in: layout))
    }

    func focusColumn(at index: Int) {
        setLayout(ColumnLayoutEngine.focusColumn(at: index, in: layout))
    }

    func focusColumn(id: Column.ID) {
        guard let index = layout.columns.firstIndex(where: { $0.id == id }) else { return }
        focusColumn(at: index)
    }

    /// Buffer đang active trong cột đang focus.
    var activeBuffer: Buffer? {
        layout.focusedColumn.activeTab.flatMap { buffers[$0.buffer] }
    }

    /// Workspace của cột đang focus (để gợi ý thư mục cho Save As).
    var focusedWorkspace: Workspace? {
        layout.focusedColumn.workspaceID.flatMap { workspace(id: $0) }
    }

    // MARK: - Lưu

    /// ⌘S trên file thường: lưu ngay.
    func saveNow(_ buffer: Buffer) {
        autosave.save(buffer)
    }

    /// Lưu mọi buffer có thay đổi (đổi tab, app mất focus, thoát app).
    func saveAllBuffers() {
        autosave.saveAll(buffers.values)
    }

    // MARK: - Ngôn ngữ

    /// Đổi ngôn ngữ của buffer (menu trên thanh trạng thái, hoặc tự nhận diện), lưu vào session.
    func setLanguage(_ language: Language, of buffer: Buffer, manual: Bool = true) {
        if manual { buffer.isLanguageManual = true }
        guard buffer.language != language else { return }
        buffer.language = language
        if case let .draft(id) = buffer.id, let index = drafts.firstIndex(where: { $0.id == id }) {
            drafts[index].language = language
        }
        onBufferLanguageChange?(buffer)
        markSessionDirty()
    }

    // MARK: - Thay đổi từ bên ngoài

    /// Thư mục (đường dẫn thật) chứa các file đang mở, để theo dõi bằng FSEvents.
    var watchedDirectories: Set<String> {
        Set(buffers.keys.compactMap { $0.fileURL.map { (Self.realPath(ofFile: $0) as NSString).deletingLastPathComponent } })
    }

    /// Kiểm tra lại các file đang mở có đường dẫn thật nằm trong `paths` (`nil` = kiểm tra tất cả).
    func checkExternalChanges(paths: Set<String>?) {
        for buffer in buffers.values {
            guard let url = buffer.id.fileURL else { continue }
            if let paths, !paths.contains(Self.realPath(ofFile: url)) { continue }
            autosave.checkDisk(buffer)
        }
    }

    func reloadFromDisk(_ buffer: Buffer) {
        autosave.reloadFromDisk(buffer)
    }

    func keepMine(_ buffer: Buffer) {
        autosave.keepMine(buffer)
    }

    // MARK: - Nháp

    /// ⌘N: tạo nháp mới, mở vào cột đang focus.
    @discardableResult
    func newDraft() throws -> UUID {
        let info = DraftInfo(id: UUID(),
                             title: DraftStore.nextTitle(existing: drafts.map(\.title)),
                             language: .markdown,
                             createdAt: Date())
        try draftStore.create(info.id)
        drafts.append(info)
        onDraftsChange?()
        register(Buffer(id: .draft(info.id), text: "", language: info.language, draftTitle: info.title))
        open(Tab(buffer: .draft(info.id), workspaceID: nil))
        markSessionDirty()
        return info.id
    }

    /// Mở nháp (click trong nhóm NHÁP) vào cột đang focus.
    func openDraft(_ id: UUID) throws {
        guard let info = drafts.first(where: { $0.id == id }) else { return }
        let bufferID = BufferID.draft(id)
        if buffers[bufferID] == nil {
            register(Buffer(id: bufferID, text: try draftStore.read(id),
                            language: info.language, draftTitle: info.title))
        }
        open(Tab(buffer: bufferID, workspaceID: nil))
    }

    /// Save As cho nháp: ghi ra `url`, buffer thành file thường, nháp bị xoá khỏi nhóm NHÁP.
    /// File nằm trong workspace đang mở → tab chuyển sang cột của workspace đó (SPEC §3.5).
    func saveDraft(_ id: UUID, to url: URL) throws {
        guard let buffer = buffers[.draft(id)] else { return }
        let fileID = BufferID.file(path: url)
        if buffers[fileID] != nil {
            // File đích đang mở ở tab khác: lưu và đóng tab đó trước khi ghi đè.
            closeTab(fileID)
        }
        let data = TextFileCodec.encode(buffer.text, lineEnding: .lf)
        try autosave.writeData(data, url)

        autosave.cancel(buffer)
        buffer.becomeFile(url)
        buffer.diskDigest = SHA256.hash(data: data)
        buffer.isDirty = false
        buffer.saveState = .saved
        buffers[.draft(id)] = nil
        buffers[fileID] = buffer

        try? draftStore.delete(id)
        drafts.removeAll { $0.id == id }
        onDraftsChange?()

        let tab = Tab(buffer: fileID, workspaceID: workspaceID(containing: url))
        setLayout(ColumnLayoutEngine.replace(.draft(id), with: tab, in: layout))
        onBufferStatusChange?(buffer)
        markSessionDirty()
    }

    // MARK: - Session

    /// Phần trạng thái do cửa sổ giữ (khung cửa sổ, sidebar, tỉ lệ độ rộng cột).
    struct WindowLayoutState {
        var window: Session.WindowState?
        var sidebar: Session.SidebarState
        /// Theo thứ tự cột.
        var columnWidthRatios: [Double]
    }

    func makeSession(window state: WindowLayoutState) -> Session {
        let columnCount = layout.columns.count
        let columns = layout.columns.enumerated().map { index, column in
            Session.ColumnState(
                workspaceId: column.workspaceID,
                widthRatio: state.columnWidthRatios.indices.contains(index)
                    ? state.columnWidthRatios[index] : 1 / Double(columnCount),
                activeIndex: column.activeIndex,
                tabs: column.tabs.map { tab in
                    switch tab.buffer {
                    case let .file(url): .file(path: url.path)
                    case let .draft(id): .draft(id: id)
                    }
                }
            )
        }
        var bufferState: [String: Session.BufferState] = [:]
        for (id, buffer) in buffers {
            bufferState[Session.key(for: id)] = Session.BufferState(
                selection: [buffer.selection.location, buffer.selection.length],
                scrollY: Double(buffer.scrollY),
                language: buffer.language
            )
        }
        return Session(
            fontSize: Double(fontSize),
            window: state.window,
            sidebar: state.sidebar,
            workspaces: workspaces.map {
                Session.WorkspaceState(id: $0.id, path: $0.url.path,
                                       expandedDirs: $0.expandedDirs.sorted(), collapsed: $0.collapsed)
            },
            drafts: drafts,
            columns: columns,
            focusedColumn: layout.focusedIndex,
            bufferState: bufferState
        )
    }

    /// Khôi phục từ session lúc mở app. Tab có file/nháp không còn thì bỏ qua (áp quy tắc đóng tab);
    /// workspace không còn thì vẫn giữ trên sidebar (đánh dấu `isMissing`).
    func restore(_ session: Session) {
        fontSize = FontSize.clamped(CGFloat(session.fontSize))
        workspaces = session.workspaces.map {
            Workspace(id: $0.id, url: URL(fileURLWithPath: $0.path),
                      expandedDirs: Set($0.expandedDirs), collapsed: $0.collapsed)
        }
        drafts = session.drafts.filter { draftStore.exists($0.id) }

        var columns: [Column] = []
        var unavailable: [BufferID] = []
        var seen = Set<BufferID>()
        for saved in session.columns {
            var tabs: [Tab] = []
            for savedTab in saved.tabs {
                let tab = restoreTab(savedTab)
                guard seen.insert(tab.buffer).inserted else { continue }
                if buffers[tab.buffer] == nil { unavailable.append(tab.buffer) }
                tabs.append(tab)
            }
            let active = saved.activeIndex.map { min(max($0, 0), tabs.count - 1) }
            columns.append(Column(workspaceID: saved.workspaceId, tabs: tabs,
                                  activeIndex: tabs.isEmpty ? nil : (active ?? 0)))
        }
        var restored = columns.isEmpty
            ? ColumnLayout.initial()
            : ColumnLayout(columns: columns, focusedIndex: min(max(session.focusedColumn, 0), columns.count - 1))
        for id in unavailable {
            restored = ColumnLayoutEngine.close(id, in: restored)
        }
        layout = restored
        let open = Set(layout.allTabs.map(\.buffer))
        buffers = buffers.filter { open.contains($0.key) }

        for (id, buffer) in buffers {
            guard let state = session.bufferState[Session.key(for: id)] else { continue }
            if state.selection.count == 2 {
                buffer.selection = NSRange(location: max(state.selection[0], 0), length: max(state.selection[1], 0))
            }
            buffer.scrollY = CGFloat(state.scrollY)
            if let language = state.language { buffer.language = language }
        }
    }

    // MARK: - Private

    /// Đường dẫn thật của file như FSEvents báo (resolve symlink); file không còn thì resolve thư mục cha.
    private static func realPath(ofFile url: URL) -> String {
        if FileManager.default.fileExists(atPath: url.path) {
            return DirectoryWatcher.realPath(url.path)
        }
        return DirectoryWatcher.realPath(url.deletingLastPathComponent().path) + "/" + url.lastPathComponent
    }

    /// Dựng tab từ session và nạp buffer nếu file/nháp còn đọc được.
    private func restoreTab(_ saved: Session.TabState) -> Tab {
        switch saved {
        case let .file(path):
            let url = URL(fileURLWithPath: path)
            let tab = Tab(buffer: .file(path: url), workspaceID: workspaceID(containing: url))
            if buffers[tab.buffer] == nil, let buffer = try? Buffer.load(url: url) {
                register(buffer)
            }
            return tab
        case let .draft(id):
            let tab = Tab(buffer: .draft(id), workspaceID: nil)
            if buffers[tab.buffer] == nil,
               let info = drafts.first(where: { $0.id == id }),
               let text = try? draftStore.read(id) {
                register(Buffer(id: tab.buffer, text: text, language: info.language, draftTitle: info.title))
            }
            return tab
        }
    }

    private func register(_ buffer: Buffer) {
        buffers[buffer.id] = buffer
        buffer.onEdit = { [weak self, weak buffer] in
            guard let self, let buffer else { return }
            self.autosave.bufferDidChange(buffer)
            // Nháp có dòng đầu `#!` → chuyển sang Bash (SPEC §3.5).
            if buffer.id.isDraft, !buffer.isLanguageManual, buffer.language == .markdown,
               Language.detectDraft(firstLine: Language.firstLine(of: buffer.text)) == .bash {
                self.setLanguage(.bash, of: buffer, manual: false)
            }
        }
    }

    private func open(_ tab: Tab) {
        setLayout(ColumnLayoutEngine.open(tab, in: layout))
    }

    private func setLayout(_ newLayout: ColumnLayout) {
        guard newLayout != layout else { return }
        // Đổi tab/đóng tab → lưu mọi thay đổi đang chờ trước.
        saveAllBuffers()
        layout = newLayout
        let open = Set(newLayout.allTabs.map(\.buffer))
        buffers = buffers.filter { open.contains($0.key) }
        onLayoutChange?()
        markSessionDirty()
    }
}

import Foundation

/// Quy tắc chia cột (SPEC §3.2). Thuần: nhận bố cục cũ, trả về bố cục mới.
enum ColumnLayoutEngine {
    /// Mở một tab (quy tắc 2, 3). Buffer đã mở ở đâu đó thì chỉ focus tab đó.
    static func open(_ tab: Tab, in layout: ColumnLayout, newColumnID: () -> UUID = { UUID() }) -> ColumnLayout {
        if layout.location(of: tab.buffer) != nil {
            return activate(tab.buffer, in: layout)
        }
        var result = layout

        // Nháp / file ngoài workspace → luôn vào cột đang focus.
        guard let workspaceID = tab.workspaceID else {
            append(tab, toColumnAt: result.focusedIndex, in: &result)
            return result
        }

        if let index = result.columns.firstIndex(where: { $0.workspaceID == workspaceID }) {
            append(tab, toColumnAt: index, in: &result)
            result.focusedIndex = index
        } else if result.columns.count == 1, result.columns[0].workspaceID == nil {
            // Cột duy nhất chưa thuộc workspace nào (trống hoặc chỉ có nháp) → nhận workspace này.
            result.columns[0].workspaceID = workspaceID
            append(tab, toColumnAt: 0, in: &result)
            result.focusedIndex = 0
        } else {
            result.columns.append(Column(id: newColumnID(), workspaceID: workspaceID))
            let index = result.columns.count - 1
            append(tab, toColumnAt: index, in: &result)
            result.focusedIndex = index
        }
        return result
    }

    /// Đóng tab (quy tắc 4).
    static func close(_ buffer: BufferID, in layout: ColumnLayout) -> ColumnLayout {
        guard let (columnIndex, tabIndex) = layout.location(of: buffer) else { return layout }
        var result = layout
        var column = result.columns[columnIndex]
        let wasActive = column.activeIndex == tabIndex
        column.tabs.remove(at: tabIndex)
        if column.tabs.isEmpty {
            column.activeIndex = nil
        } else if let active = column.activeIndex {
            if tabIndex < active {
                column.activeIndex = active - 1
            } else if wasActive {
                column.activeIndex = min(tabIndex, column.tabs.count - 1)
            }
        }
        result.columns[columnIndex] = column

        guard let workspaceID = column.workspaceID,
              !column.tabs.contains(where: { $0.workspaceID == workspaceID }) else { return result }

        // Đã đóng tab cuối cùng thuộc workspace của cột.
        guard result.columns.count > 1 else {
            result.columns[columnIndex].workspaceID = nil
            return result
        }

        let targetIndex = columnIndex > 0 ? columnIndex - 1 : columnIndex + 1
        let guests = column.tabs
        if !guests.isEmpty {
            let firstGuestIndex = result.columns[targetIndex].tabs.count
            result.columns[targetIndex].tabs.append(contentsOf: guests)
            if result.focusedIndex == columnIndex, let active = column.activeIndex {
                // Cột bị xoá đang focus → giữ tab nháp đang xem ở cột nhận.
                result.columns[targetIndex].activeIndex = firstGuestIndex + active
            } else if result.columns[targetIndex].activeIndex == nil {
                result.columns[targetIndex].activeIndex = firstGuestIndex
            }
        }
        result.columns.remove(at: columnIndex)
        if result.focusedIndex == columnIndex {
            result.focusedIndex = targetIndex > columnIndex ? columnIndex : targetIndex
        } else if result.focusedIndex > columnIndex {
            result.focusedIndex -= 1
        }
        return result
    }

    /// Gỡ workspace khỏi sidebar: đóng mọi tab của nó (quy tắc 5).
    static func removeWorkspace(_ workspaceID: UUID, from layout: ColumnLayout) -> ColumnLayout {
        var result = layout
        while let tab = result.allTabs.first(where: { $0.workspaceID == workspaceID }) {
            result = close(tab.buffer, in: result)
        }
        return result
    }

    /// Focus cột thứ `index` (⌘1…⌘9). Ngoài phạm vi thì giữ nguyên.
    static func focusColumn(at index: Int, in layout: ColumnLayout) -> ColumnLayout {
        guard layout.columns.indices.contains(index) else { return layout }
        var result = layout
        result.focusedIndex = index
        return result
    }

    /// Chọn tab đang mở và focus cột chứa nó.
    static func activate(_ buffer: BufferID, in layout: ColumnLayout) -> ColumnLayout {
        guard let (columnIndex, tabIndex) = layout.location(of: buffer) else { return layout }
        var result = layout
        result.columns[columnIndex].activeIndex = tabIndex
        result.focusedIndex = columnIndex
        return result
    }

    /// Tab kế tiếp (+1) / trước đó (−1) trong cột đang focus, quay vòng.
    static func selectAdjacentTab(offset: Int, in layout: ColumnLayout) -> ColumnLayout {
        let column = layout.focusedColumn
        guard !column.tabs.isEmpty else { return layout }
        let count = column.tabs.count
        let current = column.activeIndex ?? 0
        var result = layout
        result.columns[layout.focusedIndex].activeIndex = ((current + offset) % count + count) % count
        return result
    }

    private static func append(_ tab: Tab, toColumnAt index: Int, in layout: inout ColumnLayout) {
        layout.columns[index].tabs.append(tab)
        layout.columns[index].activeIndex = layout.columns[index].tabs.count - 1
    }
}

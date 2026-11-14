# MiniEditor — Đặc tả sản phẩm & kỹ thuật

> Tài liệu này là nguồn sự thật duy nhất. Tính năng nào không có ở đây thì **không làm**.

---

## 1. Mục tiêu

Một text editor cá nhân trên macOS để thay VSCode trong 3 việc:

1. Mở song song nhiều workspace chứa script (chỉ để copy và paste sang terminal).
2. Viết nháp prompt.
3. Sửa nhanh file bash/markdown.

Thứ tự ưu tiên: **nhẹ (ít RAM/CPU) > mượt (gõ không giật) > ít tính năng**.

### Không làm (non-goals)

LSP, autocomplete, extension/plugin, git, terminal tích hợp, minimap, tìm kiếm toàn workspace, theme light, settings UI, đa cửa sổ, đồng bộ cloud, chạy được trên macOS cũ hơn 27.

---

## 2. Môi trường & ràng buộc kỹ thuật

| Mục | Quyết định |
|---|---|
| OS | macOS 27, Apple Silicon. Deployment target đặt bản cao nhất Xcode cho chọn (lúc tạo project đang là 26.6) |
| Ngôn ngữ | Swift 6 (Strict Concurrency Checking = Complete), UI chạy trên `@MainActor` |
| UI | **AppKit thuần**. Không dùng SwiftUI, không WebView |
| Text engine | `NSTextView` dùng **TextKit 1** (`NSLayoutManager`), không dùng TextKit 2 |
| Thư viện ngoài | **Không có.** Chỉ dùng framework của Apple |
| Project | Project tạo sẵn bằng Xcode 27: `~/Work/my-projects/mini-editor/MiniEditor/MiniEditor.xcodeproj` (thư mục `mini-editor/MiniEditor/` là gốc repo git), scheme `MiniEditor`. File project dùng định dạng mới `project.xcproj` (văn bản dạng JSON), không phải `project.pbxproj`. **Commit `.xcodeproj` vào git.** Build/test bằng `xcodebuild`. Không dùng XcodeGen |
| Thư mục nguồn | `MiniEditor/MiniEditor/` (tính từ `mini-editor/`) là thư mục đồng bộ của Xcode: file Swift tạo trên đĩa trong thư mục này **tự được thêm vào target**, không cần sửa `project.xcproj` |
| Sandbox | **Đã tắt** (đã xoá capability App Sandbox khỏi target) |
| Phân phối | Build local, không lên App Store |

---

## 3. Tính năng & tiêu chí nghiệm thu

### 3.1 Workspace & sidebar

- Workspace là một thư mục trên đĩa. Thêm bằng ⌘O (`NSOpenPanel`, chỉ chọn thư mục), gỡ bằng menu chuột phải "Gỡ khỏi sidebar" (không xoá gì trên đĩa).
- Sidebar dùng `NSOutlineView` dạng source list:
  - Mỗi workspace là một nhóm có thể thu gọn, tên viết HOA.
  - Nhóm cuối luôn là **NHÁP (CHƯA LƯU TÊN)**, chứa toàn bộ file nháp.
- Cây thư mục hiện cả thư mục con. Ẩn: `.git`, `.DS_Store`, `node_modules`, `vendor`, `.idea`, `.vscode`.
- Sắp xếp trong cây: thư mục trước, file sau, mỗi nhóm theo tên A→Z (không phân biệt hoa thường, so sánh kiểu Finder).
- Tự làm mới khi trên đĩa có file/thư mục được thêm, xoá hoặc đổi tên (FSEvents, debounce 200ms).
- Click 1 lần vào file là mở file đó. File đang active trong cột đang focus được highlight trên sidebar.
- ⌘B ẩn/hiện sidebar. Kéo được độ rộng sidebar (mặc định 240px, tối thiểu 160px).
- Trạng thái mở/đóng của từng thư mục được lưu lại trong session.

### 3.2 Cột editor (quan trọng nhất)

**Định nghĩa:** mỗi cột **thuộc về một workspace**. File nháp không thuộc workspace nào, nó "ở nhờ" trong cột đang chứa nó.

Quy tắc:

1. **Số cột = số workspace khác nhau có ít nhất 1 tab đang mở**, tối thiểu 1 cột, không giới hạn số cột tối đa.
2. Mở một file:
   - Workspace của file đã có cột → mở thành tab trong cột đó và focus cột đó.
   - Chưa có cột → **tạo cột mới bên phải**, chia lại độ rộng cho đều.
   - Nếu chỉ có 1 cột và cột đó đang chỉ chứa file nháp → cột đó nhận workspace của file vừa mở (không tạo thêm cột).
3. Mở hoặc tạo file nháp (⌘N) → luôn vào **cột đang focus**, không bao giờ tạo cột mới.
4. Đóng tab cuối cùng thuộc workspace của một cột:
   - Nếu cột còn file nháp và còn cột khác → chuyển các file nháp sang cột liền kề bên trái (không có thì bên phải), rồi xoá cột.
   - Nếu đây là cột duy nhất → giữ cột, cột trở thành "cột không thuộc workspace nào".
5. Gỡ một workspace khỏi sidebar → đóng mọi tab của workspace đó, áp dụng quy tắc 4.
6. Kéo được thanh chia giữa các cột. Độ rộng tối thiểu mỗi cột là 200px; người dùng tự đóng bớt cột khi màn hình quá hẹp, app không tự gộp.
7. Thứ tự các cột là thứ tự tạo ra (cột mới luôn ở bên phải).

Logic trên phải nằm trong một kiểu **thuần (pure)**, không phụ thuộc AppKit (`ColumnLayoutEngine`), để viết unit test được.

### 3.3 Tab

- Mỗi cột có thanh tab riêng. Một file chỉ được mở ở **tối đa 1 tab** trong toàn app.
- Tab hiện tên file. Tab nháp hiện tên nháp, chữ nghiêng.
- Có nút × trên tab. ⌘W đóng tab đang active. ⌃Tab / ⌃⇧Tab chuyển tab trong cột.
- Đóng tab **không bao giờ hỏi lưu**, vì nội dung luôn đã được tự lưu.
- Không có tab xem trước (preview tab), không kéo tab giữa các cột.

### 3.4 Tự động lưu

| Loại buffer | Lưu vào đâu | Khi nào lưu |
|---|---|---|
| File đã có đường dẫn | **Ghi thẳng vào file gốc** | 500ms sau lần gõ cuối; khi đổi tab; khi app mất focus; khi thoát app |
| File nháp | `~/Library/Application Support/MiniEditor/drafts/<uuid>.txt` | 300ms sau lần gõ cuối; và các thời điểm như trên |

Yêu cầu khi ghi file gốc:

- Ghi atomic (file tạm rồi `rename`).
- **Giữ nguyên quyền POSIX của file** (đặc biệt là quyền thực thi `+x` của script `.sh`). Sau khi ghi atomic, đọc lại quyền cũ và set lại cho file mới.
- Giữ kiểu xuống dòng (LF/CRLF) phát hiện được lúc mở file. Encoding mặc định UTF-8; file không đọc được bằng UTF-8 thì mở ở chế độ chỉ đọc kèm cảnh báo.
- Ghi lỗi (mất quyền ghi, ổ đầy…) → hiện banner đỏ trên editor, giữ nội dung trong RAM và thử lại ở lần lưu kế tiếp.

**Khôi phục sau crash:** mở lại app phải thấy đúng các workspace, cột, tab, tab đang active, vị trí con trỏ và vị trí cuộn. Chấp nhận mất tối đa ~1 giây gõ cuối cùng.

### 3.5 File nháp

- ⌘N tạo nháp mới tên `Chưa đặt tên-N`, với N là số nhỏ nhất chưa có ai dùng.
- Ngôn ngữ mặc định của nháp là **Markdown**. Nếu dòng đầu bắt đầu bằng `#!` thì chuyển sang Bash.
- Đóng tab nháp **không xoá** nháp: nháp vẫn nằm trong nhóm NHÁP trên sidebar.
- Xoá nháp: chuột phải trên sidebar → "Xoá nháp" → hỏi xác nhận → xoá hẳn file trong thư mục `drafts`.
- Đổi tên nháp: chuột phải → "Đổi tên" (chỉ đổi tên hiển thị).
- ⌘S trên tab nháp → hiện `NSSavePanel`:
  - Lưu xong, buffer trở thành file thường và nháp bị xoá khỏi nhóm NHÁP.
  - Nếu file nằm trong một workspace đang mở, tab chuyển sang cột của workspace đó (áp dụng quy tắc 3.2).
- ⌘S trên file thường → lưu ngay, không đợi hết thời gian chờ.

### 3.6 File bị sửa từ bên ngoài

Người dùng chạy song song PhpStorm/VSCode, nên một file có thể bị sửa ở 2 nơi.

- Theo dõi các file đang mở (DispatchSource/FSEvents). Bỏ qua thay đổi do chính app ghi (so sánh hash hoặc thời gian sửa của lần ghi gần nhất).
- Có thay đổi từ bên ngoài:
  - Buffer **không có thay đổi chưa lưu** → tự nạp lại nội dung, giữ vị trí con trỏ và cuộn ở mức gần nhất có thể.
  - Buffer **đang có thay đổi chưa lưu** (đang trong thời gian chờ) → tạm dừng tự lưu cho buffer đó và hiện banner: "File đã bị sửa bên ngoài — [Nạp bản trên đĩa] [Giữ bản của tôi]".
- File bị xoá hoặc đổi tên từ bên ngoài → tab vẫn giữ nội dung, hiện banner "File không còn trên đĩa — [Lưu lại] [Đóng tab]".

### 3.7 Font

- Thứ tự fallback: `Menlo` → `Monaco` → `Courier New` → `NSFont.monospacedSystemFont`. Không cho đổi font family.
- ⌘+ / ⌘− tăng/giảm 1pt, ⌘0 về mặc định. Khoảng cho phép 9–32pt, mặc định 13pt.
- Cỡ chữ áp dụng chung cho mọi editor và được lưu vào session.
- Line height bằng 1.5 lần cỡ chữ. Tab = 4 khoảng trắng hiển thị; giữ nguyên ký tự gốc (tab hay space) có trong file.

### 3.8 Tô màu cú pháp

Nhận diện ngôn ngữ:

| Ngôn ngữ | Điều kiện |
|---|---|
| Bash | Đuôi `.sh` `.bash` `.zsh` `.command`, hoặc dòng đầu là shebang chứa `sh`/`bash`/`zsh` |
| Markdown | Đuôi `.md` `.markdown`; file nháp mặc định |
| Plain | Còn lại |

Click vào tên ngôn ngữ trên thanh trạng thái → menu Plain / Bash / Markdown để đổi tay (áp dụng cho buffer đó, lưu trong session).

**Token cho Bash:** comment (`#` đứng đầu dòng hoặc sau khoảng trắng, không nằm trong chuỗi, không phải `$#`), chuỗi `"..."` và `'...'`, biến (`$VAR`, `${...}`, `$1`, `$@`, `$?`…, kể cả khi nằm trong chuỗi nháy kép), từ khoá (`if then else elif fi for while until do done case esac function in select return`), builtin (`export local readonly source alias unalias echo printf cd exit set unset shift trap eval exec`). V1 chưa cần xử lý heredoc.

**Token cho Markdown:** heading (`^#{1,6} `), in đậm `**x**`/`__x__`, in nghiêng `*x*`/`_x_`, inline code `` `x` ``, khối code ```` ``` ```` (tô màu cả khối), dấu đầu dòng của list (`-` `*` `+` `1.`), blockquote `>`, link `[text](url)`.

Yêu cầu hiệu năng:

- Dùng **temporary attributes** của `NSLayoutManager` để tô màu, không sửa `NSTextStorage` (để không ảnh hưởng undo và nhanh hơn).
- Mỗi lần sửa chỉ tô lại **các dòng bị ảnh hưởng**. Riêng khối code trong Markdown cần tính lại vị trí các dấu ```` ``` ```` (quét nhanh theo dòng), rồi tô lại vùng thay đổi.
- File > 2MB → tắt tô màu. File > 20MB → hỏi trước khi mở.

### 3.9 Thanh trạng thái

Gồm: ngôn ngữ (click được để đổi) · `UTF-8` · `Dòng X, Cột Y` · `Cỡ chữ N` · trạng thái lưu (`● Đã lưu tự động` / `Đang lưu…` / `⚠ Lỗi lưu`).

### 3.10 Phím tắt

| Phím | Hành động |
|---|---|
| ⌘N | Tạo file nháp mới (vào cột đang focus) |
| ⌘O | Thêm workspace |
| ⌘S | Lưu ngay (file nháp thì mở Save As) |
| ⌘W | Đóng tab |
| ⌘B | Ẩn/hiện sidebar |
| ⌘+ / ⌘− / ⌘0 | Cỡ chữ |
| ⌘F / ⌘G / ⌘⇧G | Tìm trong file (find bar có sẵn của `NSTextView`) |
| ⌘1 … ⌘9 | Focus cột thứ N |
| ⌃Tab / ⌃⇧Tab | Tab kế tiếp / trước đó trong cột |
| ⌘/ | Bật/tắt comment dòng (Bash: `# `; Markdown: không làm gì) |

---

## 4. Theme (chỉ có dark)

Khoá giao diện ở dark: `NSApp.appearance = NSAppearance(named: .darkAqua)`. Mọi màu lấy từ một chỗ duy nhất là `Theme.swift`.

| Token | Hex | Dùng cho |
|---|---|---|
| `editorBackground` | `#1E1F22` | Nền editor, tab đang active |
| `sidebarBackground` | `#18191B` | Nền sidebar |
| `chromeBackground` | `#2B2D30` | Title bar, thanh tab, thanh trạng thái |
| `border` | `#3A3C40` | Viền ngoài, thanh chia cột |
| `borderSubtle` | `#2E3034` | Viền bên trong |
| `text` | `#D4D4D4` | Chữ chính, con trỏ |
| `textMuted` | `#9DA0A6` | Tab không active, tiêu đề nhóm sidebar |
| `lineNumber` | `#858890` | Số dòng |
| `selectionRow` | `#2C3A4F` | Dòng đang chọn trên sidebar |
| `textSelection` | `#264F78` | Vùng chọn văn bản |
| `accent` | `#79B8FF` | Gạch trên tab active của cột đang focus |
| `syntaxKeyword` | `#D19FE0` | Từ khoá/builtin Bash, dấu list Markdown |
| `syntaxString` | `#A6D189` | Chuỗi, inline code, khối code |
| `syntaxComment` | `#8B949E` (nghiêng) | Comment |
| `syntaxVariable` | `#79B8FF` | Biến Bash |
| `syntaxHeading` | `#79B8FF` (đậm) | Heading Markdown |

Tham khảo wireframe: canvas "Wireframe bố cục Text Editor macOS", các artboard *B dark*.

---

## 5. Kiến trúc

```
mini-editor/MiniEditor/           # gốc repo git
├─ MiniEditor.xcodeproj
├─ SPEC.md
├─ CLAUDE.md
├─ MiniEditor/                   # thư mục đồng bộ của Xcode (code app)
│  ├─ Assets.xcassets
│  ├─ App/
│  │  ├─ main.swift / AppDelegate.swift
│  │  └─ MainMenu.swift          # dựng menu và phím tắt bằng code, không dùng storyboard/xib
│  ├─ Model/
│  │  ├─ Workspace.swift          # id, url, tên
│  │  ├─ Buffer.swift             # id, kind (.file(URL) | .draft(UUID)), NSTextStorage, language, trạng thái lưu
│  │  ├─ Column.swift             # workspaceID?, tabs [BufferID], activeIndex
│  │  ├─ ColumnLayoutEngine.swift # PURE: áp quy tắc 3.2, trả về [Column] mới
│  │  └─ AppState.swift           # @MainActor, nguồn sự thật duy nhất cho UI
│  ├─ Persistence/
│  │  ├─ AutosaveService.swift    # debounce, ghi atomic, giữ quyền file
│  │  ├─ DraftStore.swift
│  │  ├─ SessionStore.swift       # đọc/ghi session.json
│  │  └─ FileWatcher.swift        # FSEvents (thư mục) + DispatchSource (file đang mở)
│  ├─ UI/
│  │  ├─ MainWindowController.swift  # NSSplitViewController: sidebar | vùng cột
│  │  ├─ Sidebar/SidebarViewController.swift
│  │  ├─ Editor/ColumnsViewController.swift  # NSSplitView, thêm/bớt cột động
│  │  ├─ Editor/EditorColumnView.swift       # thanh tab + NSScrollView/NSTextView
│  │  ├─ Editor/CodeTextView.swift           # subclass NSTextView
│  │  ├─ Editor/LineNumberRulerView.swift
│  │  ├─ StatusBarView.swift
│  │  └─ Theme.swift
│  └─ Highlight/
│     ├─ Highlighter.swift        # protocol: tokens(in: NSRange, of: String) -> [Token]
│     ├─ BashHighlighter.swift
│     └─ MarkdownHighlighter.swift
└─ MiniEditorTests/              # target Unit Testing Bundle
   ├─ ColumnLayoutEngineTests.swift
   ├─ BashHighlighterTests.swift
   ├─ MarkdownHighlighterTests.swift
   ├─ SessionStoreTests.swift
   └─ AutosaveServiceTests.swift  # đặc biệt: giữ quyền +x, giữ CRLF
```

Nguyên tắc:

- Mỗi buffer có đúng 1 `NSTextStorage`. Vì mỗi file chỉ mở ở 1 tab, không cần chia sẻ storage giữa các view.
- Chuyển tab chỉ đổi `textStorage` gắn vào layout manager của cột, không tạo lại view.
- UI lắng nghe `AppState` qua delegate/closure (hoặc Observation framework). Không dùng Combine nếu không thật cần.
- Không dùng singleton toàn cục, trừ `Theme`.

---

## 6. Dữ liệu lưu trên đĩa

Thư mục: `~/Library/Application Support/MiniEditor/`

```
session.json
drafts/<uuid>.txt
```

`session.json` (ghi atomic, debounce 1 giây, và ghi khi thoát app):

```json
{
  "version": 1,
  "fontSize": 13,
  "window": { "frame": "{{100, 100}, {1400, 860}}" },
  "sidebar": { "visible": true, "width": 240 },
  "workspaces": [
    { "id": "UUID", "path": "/Users/son/scripts/ops-scripts", "expandedDirs": ["deploy"], "collapsed": false }
  ],
  "drafts": [
    { "id": "UUID", "title": "Chưa đặt tên-1", "language": "markdown", "createdAt": "2026-11-14T15:00:00Z" }
  ],
  "columns": [
    {
      "workspaceId": "UUID or null",
      "widthRatio": 0.5,
      "activeIndex": 0,
      "tabs": [
        { "kind": "file", "path": "/Users/son/scripts/ops-scripts/deploy/deploy-prod.sh" },
        { "kind": "draft", "id": "UUID" }
      ]
    }
  ],
  "focusedColumn": 0,
  "bufferState": {
    "<path hoặc draft-id>": { "selection": [120, 0], "scrollY": 0, "language": "bash" }
  }
}
```

Khi khôi phục: file trong `tabs` không còn tồn tại thì bỏ qua tab đó; workspace không còn tồn tại thì vẫn giữ trên sidebar nhưng hiện màu mờ kèm "(không tìm thấy)".

---

## 7. Ngân sách hiệu năng

Đo bằng Instruments trên MacBook Pro M1 Pro, bản build Release:

| Chỉ số | Mục tiêu |
|---|---|
| Khởi động lạnh tới khi gõ được (khôi phục 2 workspace, 6 tab) | < 400ms |
| RAM lúc rảnh (2 workspace, 10 tab, file < 50KB) | < 60MB |
| CPU lúc rảnh | ~0% (không có timer chạy liên tục) |
| Độ trễ phím trên file 5.000 dòng | Không cảm nhận được, mỗi lần tô màu < 2ms |
| Dung lượng app | < 10MB |

---

## 8. Lộ trình

Mỗi milestone làm trong một phiên riêng. Xong một milestone → build, chạy test, dừng lại để người dùng review trước khi làm tiếp. Đánh dấu `[x]` khi xong.

- [x] **M0 — Khung project** (project đã được tạo sẵn bằng Xcode từ template SwiftUI):
  - Xoá `ContentView.swift` và `MyApp.swift` (template SwiftUI). Thay bằng `main.swift` + `AppDelegate.swift` thuần AppKit, dựng menu bằng code.
  - Trong `project.xcproj`: Swift Language Version = 6, Strict Concurrency Checking = Complete, macOS Deployment Target = bản cao nhất SDK hỗ trợ, đổi Bundle Identifier khỏi `devplaceholder.…`. Kiểm tra không còn entitlement App Sandbox.
  - Thêm target Unit Testing Bundle `MiniEditorTests`. Nếu không sửa `project.xcproj` một cách an toàn được thì dừng lại, nhờ người dùng tạo bằng Xcode (File › New › Target › Unit Testing Bundle).
  - Thêm `.gitignore` (`build/`, `xcuserdata/`, `.DS_Store`).
  - Nghiệm thu: app mở được một cửa sổ dark trống; lệnh build và test trong `CLAUDE.md` chạy thành công.
- [x] **M1 — Một editor:** `CodeTextView` dùng TextKit 1, font và fallback, ⌘+/⌘−/⌘0, số dòng, theme, thanh trạng thái (Dòng/Cột, Cỡ chữ).
- [x] **M2 — Sidebar:** thêm/gỡ workspace, cây thư mục, nhóm NHÁP (chưa cần nội dung), FSEvents, ⌘B.
- [ ] **M3 — Tab & cột:** `ColumnLayoutEngine` có đủ unit test cho mọi quy tắc 3.2, `ColumnsViewController` thêm/bớt cột động, thanh tab, các phím tắt tab/cột.
- [ ] **M4 — Tự động lưu & session:** AutosaveService (giữ quyền file, giữ kiểu xuống dòng), DraftStore, ⌘N, ⌘S/Save As, SessionStore và khôi phục đầy đủ. Test: tắt app bằng `kill -9` rồi mở lại.
- [ ] **M5 — File bị sửa từ bên ngoài:** theo dõi file đang mở, tự nạp lại, các banner xung đột/bị xoá.
- [ ] **M6 — Tô màu:** Bash và Markdown, chỉ tô lại vùng thay đổi, menu đổi ngôn ngữ, ⌘/.
- [ ] **M7 — Hoàn thiện:** đo hiệu năng theo mục 7 và tối ưu, đổi tên/xoá nháp, xử lý các trường hợp biên, icon app, build Release.

---

## 9. Nhật ký quyết định

| # | Quyết định | Lý do |
|---|---|---|
| D1 | AppKit thuần, không SwiftUI/Electron/Tauri | Nhẹ nhất, `NSTextView` có sẵn undo, find, IME tiếng Việt |
| D2 | TextKit 1 | Ổn định hơn TextKit 2 khi tô màu cú pháp |
| D3 | Bố cục B: sidebar chung + mỗi workspace một cột | Người dùng chọn qua wireframe |
| D4 | Không giới hạn số cột, người dùng tự đóng bớt | Người dùng chốt |
| D5 | File nháp không tạo cột, mở vào cột đang focus | Người dùng chốt |
| D6 | Chỉ có dark mode | Người dùng chốt |
| D7 | File có đường dẫn thì tự lưu thẳng vào file gốc | Người dùng chốt |
| D8 | Tô màu bằng regex, chưa dùng tree-sitter | Bash/Markdown đơn giản, không cần thư viện ngoài. Xem xét lại nếu tô sai nhiều |
| D9 | Không có phím tắt copy nhanh | Người dùng chốt |
| D10 | Dùng project tạo bằng Xcode và commit `.xcodeproj`, bỏ XcodeGen | Người dùng đã tạo sẵn project. Thư mục đồng bộ của Xcode giúp agent thêm file mà không cần sửa `project.xcproj` |
| D11 | Giữ cấu trúc lồng: repo git ở `mini-editor/MiniEditor/`, code ở `mini-editor/MiniEditor/MiniEditor/` | Người dùng chốt (giữ nguyên project Xcode đã tạo) |

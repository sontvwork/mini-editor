# CLAUDE.md — MiniEditor

Text editor tối giản cho macOS 27 (cá nhân dùng): nhiều workspace song song trong một cửa sổ, tự động lưu, tô màu Bash/Markdown, chỉ có dark mode.

**Đọc `SPEC.md` trước khi làm bất cứ việc gì.** SPEC.md là nguồn sự thật duy nhất; nếu yêu cầu trong phiên mâu thuẫn với SPEC.md, hỏi lại trước khi code.

## Quy tắc bắt buộc

- Swift 6, strict concurrency. UI là `@MainActor`.
- **AppKit thuần.** Không SwiftUI, không WebView, không storyboard/xib (dựng UI bằng code).
- `NSTextView` dùng **TextKit 1**. Không chuyển sang TextKit 2.
- **Không thêm thư viện ngoài** (SPM/CocoaPods/Carthage). Chỉ dùng framework của Apple.
- **Không thêm tính năng ngoài SPEC.md**, kể cả tính năng nhỏ "tiện tay". Có ý tưởng thì ghi vào cuối câu trả lời để người dùng quyết.
- Màu sắc chỉ lấy từ `Theme.swift`. Không hard-code hex ở chỗ khác.
- Logic chia cột nằm trong `ColumnLayoutEngine` (thuần, không import AppKit) và phải có unit test.
- Không timer chạy liên tục. Mọi việc nền đều theo sự kiện + debounce.
- Ghi file gốc: atomic + giữ nguyên quyền POSIX (+x) + giữ kiểu xuống dòng.

## Project

- Gốc repo git là `mini-editor/MiniEditor/` (thư mục chứa file này). Project tạo bằng Xcode 27: `MiniEditor.xcodeproj`, scheme `MiniEditor`, file project là `project.xcproj` (định dạng mới dạng JSON, không có `project.pbxproj`). `.xcodeproj` được commit vào git.
- Code app nằm trong `MiniEditor/` (tính từ gốc repo). Đây là thư mục đồng bộ của Xcode: tạo file `.swift` trong đó là file tự vào target. **Không sửa `project.xcproj` trừ khi thật cần** (đổi build setting, thêm target). Nếu phải sửa thì sửa tối thiểu, build lại ngay để kiểm tra.
- Test nằm trong `MiniEditorTests/`.
- App Sandbox đã tắt. Đừng bật lại.

## Lệnh

Chạy từ gốc repo. Nếu `xcode-select` đang trỏ Command Line Tools thì đặt `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` trước.

```bash
xcodebuild -project MiniEditor.xcodeproj -scheme MiniEditor -configuration Debug -derivedDataPath build build
xcodebuild -project MiniEditor.xcodeproj -scheme MiniEditor -derivedDataPath build test -destination 'platform=macOS'
open build/Build/Products/Debug/MiniEditor.app
```

## Cách làm việc

1. Mỗi phiên chỉ làm **một milestone** trong `SPEC.md` mục 8.
2. Trước khi code: tóm tắt ngắn kế hoạch cho milestone đó (file nào tạo/sửa).
3. Xong: build sạch, không warning mới, chạy toàn bộ test, đánh dấu `[x]` trong SPEC.md.
4. Dừng lại, báo cáo: đã làm gì, cách tự kiểm tra bằng tay, việc còn dở.
5. Commit nhỏ, message tiếng Anh dạng `feat(columns): ...`, `fix(autosave): ...`.

## Bẫy đã biết

- `NSTextView` mặc định bật smart quotes / smart dashes / autocorrect / text replacement → **tắt hết** (phá script bash).
- Tô màu bằng `layoutManager.addTemporaryAttribute`, không sửa `textStorage` (tránh làm bẩn undo và tránh gọi lại `didProcessEditing`).
- `Data.write(options: .atomic)` tạo file mới → mất quyền +x nếu không set lại.
- Tự ghi file sẽ kích hoạt file watcher của chính mình → phải lọc thay đổi do app tự ghi.
- Chuyển tab: đổi `NSTextStorage` của layout manager, đừng tạo lại `NSTextView` (tốn RAM, mất trạng thái find bar).
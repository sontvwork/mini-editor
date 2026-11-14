import Foundation

/// Bảng vị trí (UTF-16) đầu mỗi dòng của một chuỗi. Coi `\n`, `\r\n`, `\r` là một lần xuống dòng.
/// Chuỗi kết thúc bằng xuống dòng có thêm một dòng rỗng cuối (giống editor thông thường).
struct LineIndex: Equatable {
    private(set) var lineStarts: [Int] = [0]

    init(_ string: NSString) {
        let length = string.length
        guard length > 0 else { return }
        let chunkSize = 4096
        var buffer = [unichar](repeating: 0, count: chunkSize)
        var location = 0
        var pendingCR = false
        while location < length {
            let count = min(chunkSize, length - location)
            buffer.withUnsafeMutableBufferPointer { ptr in
                string.getCharacters(ptr.baseAddress!, range: NSRange(location: location, length: count))
            }
            for i in 0..<count {
                let char = buffer[i]
                let offset = location + i
                if pendingCR {
                    pendingCR = false
                    if char == 0x0A { // \r\n: dòng mới bắt đầu sau \n
                        lineStarts.append(offset + 1)
                        continue
                    }
                    lineStarts.append(offset) // \r đứng một mình
                }
                if char == 0x0A {
                    lineStarts.append(offset + 1)
                } else if char == 0x0D {
                    pendingCR = true
                }
            }
            location += count
        }
        if pendingCR { lineStarts.append(length) }
    }

    var lineCount: Int { lineStarts.count }

    func lineStart(_ line: Int) -> Int { lineStarts[line] }

    /// Chỉ số dòng (0-based) chứa vị trí `offset`.
    func line(containing offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}

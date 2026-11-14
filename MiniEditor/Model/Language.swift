import Foundation

/// Ngôn ngữ của buffer (SPEC §3.8).
enum Language: String, Codable, Sendable, CaseIterable {
    case plain
    case bash
    case markdown

    private static let bashExtensions: Set<String> = ["sh", "bash", "zsh", "command"]
    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let shellInterpreters: Set<String> = ["sh", "bash", "zsh"]

    /// Nhận diện file theo đuôi, rồi theo shebang dòng đầu.
    static func detect(fileName: String, firstLine: Substring) -> Language {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if bashExtensions.contains(ext) { return .bash }
        if markdownExtensions.contains(ext) { return .markdown }
        return isShellShebang(firstLine) ? .bash : .plain
    }

    /// Nháp mặc định là Markdown; dòng đầu bắt đầu bằng `#!` thì là Bash (SPEC §3.5).
    static func detectDraft(firstLine: Substring) -> Language {
        firstLine.hasPrefix("#!") ? .bash : .markdown
    }

    /// `#!/bin/bash`, `#!/usr/bin/env zsh`, `#!/bin/sh -e`…
    static func isShellShebang(_ line: Substring) -> Bool {
        guard line.hasPrefix("#!") else { return false }
        let parts = line.dropFirst(2).split(separator: " ", omittingEmptySubsequences: true)
        guard let first = parts.first else { return false }
        var interpreter = (String(first) as NSString).lastPathComponent
        if interpreter == "env", parts.count > 1 {
            interpreter = String(parts[1])
        }
        return shellInterpreters.contains(interpreter)
    }

    static func firstLine(of text: String) -> Substring {
        text.prefix { $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
    }
}

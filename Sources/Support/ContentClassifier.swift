import Foundation

/// Эвристики типизации текста. Ошибка классификации влияет только на иконку
/// и на моноширинный шрифт в preview — поэтому эвристики намеренно простые
/// и дешёвые (O(n) по первым нескольким килобайтам).
enum ContentClassifier {
    private static let inspectionLimit = 4_096

    static func kind(forText text: String) -> ItemKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }
        if isLink(trimmed) { return .link }
        if looksLikeCode(String(trimmed.prefix(inspectionLimit))) { return .code }
        return .text
    }

    static func isLink(_ trimmed: String) -> Bool {
        guard !trimmed.contains(where: \.isWhitespace) else { return false }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "ftp", "ftps", "mailto", "file", "ssh"].contains(scheme) && url.host != nil
            || scheme == "mailto"
    }

    private static func looksLikeCode(_ sample: String) -> Bool {
        let lines = sample.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else {
            // Однострочник считаем кодом только при явных маркерах.
            return sample.contains("=>") || sample.contains("();") || sample.hasPrefix("$ ")
        }

        var score = 0
        let indentedLines = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }
        if Double(indentedLines.count) / Double(lines.count) > 0.25 { score += 2 }

        let markers = ["{", "}", ";", "=>", "->", "func ", "def ", "class ", "import ", "return ", "</", "/>", "#include", "const ", "let ", "var "]
        let hits = markers.reduce(into: 0) { partial, marker in
            if sample.contains(marker) { partial += 1 }
        }
        score += min(hits, 3)
        return score >= 3
    }
}

enum TextNormalizer {
    /// Нормализация для поиска: регистр, диакритика, ширина символов.
    /// Применяется только к поисковому индексу — оригинал пользователя не меняется.
    static func normalize(_ string: String) -> String {
        string.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}

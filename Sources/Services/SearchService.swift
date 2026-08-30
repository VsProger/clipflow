import Foundation

/// Поиск по истории.
///
/// Реализован в памяти, а не через `#Predicate`: при лимите в десятки-сотни
/// элементов линейный проход по предвычисленному `searchIndex` быстрее любого
/// SQL-предиката и, в отличие от него, корректно работает с диакритикой,
/// регистром и Unicode. Дебаунс не нужен — проход укладывается в микросекунды.
enum SearchService {
    /// Строка, по которой элемент будет находиться.
    /// Для изображений индексируем метаданные: тип, формат, размеры, дату, приложение-источник.
    static func makeIndex(for capture: ClipboardCapture, kind: ItemKind, stored: StoredImage?) -> String {
        var components: [String] = [kind.displayName]

        switch capture.payload {
        case .text(let text):
            components.append(text)
        case .image(_, let format):
            components.append(format.displayName)
            components.append("image screenshot picture")
            if let stored {
                components.append("\(Int(stored.pixelSize.width))x\(Int(stored.pixelSize.height))")
            }
        }

        if let name = capture.source?.name { components.append(name) }
        components.append(dateTokens(for: capture.capturedAt))

        return TextNormalizer.normalize(components.joined(separator: " "))
    }

    private static func dateTokens(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMMd")
        return formatter.string(from: date)
    }

    /// Фильтрация с ранжированием. Совпадение с начала строки важнее,
    /// совпадение на границе слова важнее совпадения внутри слова.
    static func filter(_ items: [ClipboardItem], query: String) -> [ClipboardItem] {
        let normalized = TextNormalizer.normalize(query).trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return items }

        let terms = normalized.split(separator: " ").map(String.init)

        let scored: [(item: ClipboardItem, score: Int)] = items.compactMap { item in
            var total = 0
            for term in terms {
                guard let score = score(for: term, in: item.searchIndex) else { return nil }
                total += score
            }
            // Закреплённые не должны уезжать вниз из-за ранжирования.
            if item.isPinned { total += 1_000 }
            return (item, total)
        }

        return scored
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.item.updatedAt > rhs.item.updatedAt
            }
            .map(\.item)
    }

    /// nil — терм не найден, элемент отбрасывается.
    private static func score(for term: String, in index: String) -> Int? {
        guard let range = index.range(of: term) else { return nil }
        if range.lowerBound == index.startIndex { return 100 }
        let previous = index.index(before: range.lowerBound)
        let isWordBoundary = !index[previous].isLetter && !index[previous].isNumber
        return isWordBoundary ? 50 : 10
    }
}

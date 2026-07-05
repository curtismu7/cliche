import Foundation

/// Case-insensitive subsequence matching for type-to-filter search.
public enum FuzzyMatcher {
    /// True when every character of `query` appears in `text` in order
    /// (not necessarily adjacent). Empty queries match everything.
    public static func matches(_ query: String, in text: String) -> Bool {
        guard !query.isEmpty else { return true }
        var queryIndex = query.startIndex
        let query = query.lowercased()
        for character in text.lowercased() {
            if character == query[queryIndex] {
                queryIndex = query.index(after: queryIndex)
                if queryIndex == query.endIndex { return true }
            }
        }
        return false
    }

    /// Filters history items. Text items match on their content; image items
    /// only appear while the query is empty (they have no searchable text).
    public static func filter(_ items: [ClipItem], query: String) -> [ClipItem] {
        guard !query.isEmpty else { return items }
        return items.filter { item in
            guard case .text(let text) = item.kind else { return false }
            return matches(query, in: text)
        }
    }
}

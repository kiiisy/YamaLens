import Foundation

struct MountainSearchService: Sendable {
    func search(mountains: [Mountain], query: String) -> [Mountain] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return mountains
        }

        return mountains.filter { mountain in
            normalize(mountain.searchableText).contains(normalizedQuery)
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "　", with: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }
}

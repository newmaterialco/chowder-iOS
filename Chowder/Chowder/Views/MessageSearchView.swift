import SwiftUI
import Combine

struct MessageSearchView: View {
    let messages: [Message]
    @Binding var isPresented: Bool
    var onResultTapped: (UUID) -> Void

    @State private var query = ""
    @State private var results: [Message] = []
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.gray)

                    TextField("Search messages...", text: $query)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button("Cancel") {
                    isPresented = false
                }
                .font(.system(size: 15))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            // Results
            if !query.isEmpty {
                if results.isEmpty {
                    VStack(spacing: 8) {
                        Text("No results")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .background(Color(.systemBackground).opacity(0.95))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(results) { message in
                                Button {
                                    onResultTapped(message.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(message.role == .user ? "You" : "Assistant")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(message.role == .user ? .blue : .green)

                                            Text(message.timestamp, style: .relative)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }

                                        Text(highlightedSnippet(message.content, query: query))
                                            .font(.system(size: 14))
                                            .foregroundStyle(.primary)
                                            .lineLimit(3)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(.systemBackground).opacity(0.95))
                    .frame(maxHeight: 300)
                }
            }
        }
        .onAppear {
            isFocused = true
        }
        .onChange(of: query) {
            performSearch()
        }
    }

    /// Debounced search — filters messages matching the query (case-insensitive).
    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        results = messages.filter { msg in
            msg.content.lowercased().contains(trimmed)
        }
    }

    /// Build an attributed snippet with the query highlighted.
    private func highlightedSnippet(_ content: String, query: String) -> AttributedString {
        let snippet = String(content.prefix(200))
        var attributed = AttributedString(snippet)

        let lowSnippet = snippet.lowercased()
        let lowQuery = query.lowercased()

        var searchStart = lowSnippet.startIndex
        while let range = lowSnippet.range(of: lowQuery, range: searchStart..<lowSnippet.endIndex) {
            let attrRange = AttributedString.Index(range.lowerBound, within: attributed)
            let attrEnd = AttributedString.Index(range.upperBound, within: attributed)
            if let start = attrRange, let end = attrEnd {
                attributed[start..<end].backgroundColor = .yellow.opacity(0.3)
                attributed[start..<end].font = .system(size: 14, weight: .semibold)
            }
            searchStart = range.upperBound
        }

        return attributed
    }
}

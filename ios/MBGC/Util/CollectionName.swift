import Foundation

/// Helpers for collection / list names used across import, create, and rename flows.
/// Previously duplicated as a `private func sanitizeName` in ImportView.swift and
/// VibesView.swift — keep the logic here so behaviour stays in sync.
enum CollectionName {
    /// Strip brackets (used by smart-list rule IDs) and cap the length at 50.
    /// Empty strings are returned unchanged so callers can guard their own UI.
    static func sanitize(_ name: String) -> String {
        let maxLength = 50
        let stripped = name.filter { $0 != "[" && $0 != "]" }
        return String(stripped.prefix(maxLength))
    }

    /// Trim whitespace/newlines. Returns "" for whitespace-only input.
    static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Convenience: trim then sanitize.
    static func prepareForSave(_ name: String) -> String {
        sanitize(trimmed(name))
    }
}

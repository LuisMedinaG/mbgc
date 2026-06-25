import Foundation

@MainActor
@Observable
final class ImportViewModel {
    // ponytail: bggUsername stored here for Option A (full BGG username sync).
    // Not used yet — CSV import is the only active path (Option D).
    var bggUsername: String = ""
    var isSyncing = false
    var errorMessage: String?

    func load() async {
        // ponytail: BGG username sync is server-side; deferred to Option A.
        // No network on appear.
    }

    func sync() async {
        // ponytail: BGG username sync not yet implemented locally.
        // This will be replaced in Option A with a direct BGG /collection call.
        errorMessage = "BGG sync coming soon. Use CSV import for now."
    }
}

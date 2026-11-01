import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults(suiteName: FilterSettings.appGroup)
    @Published var value: FilterSettings {
        didSet { value.save(to: defaults) }
    }
    var sharedStorageAvailable: Bool { defaults != nil }

    init() {
        value = FilterSettings.load(from: UserDefaults(suiteName: FilterSettings.appGroup))
    }
}

struct ManualReviewRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let message: String
    let probability: Double
    let suggestedSTOP: Bool
}

@MainActor
final class HistoryStore: ObservableObject {
    static let file = "manual-history.enc"
    @Published private(set) var records: [ManualReviewRecord] = []

    init() { records = SecureArchive.read([ManualReviewRecord].self, file: Self.file) ?? [] }

    func add(message: String, result: JevEvaluation) {
        let item = ManualReviewRecord(id: UUID(), timestamp: Date(), message: message,
                                      probability: result.probability, suggestedSTOP: result.matches)
        let next = Array(([item] + records).prefix(100))
        do {
            try SecureArchive.write(next, file: Self.file)
            records = next
        } catch {
            // If encryption/persistence fails, do not falsely represent the result as saved.
        }
    }

    func clear() {
        SecureArchive.erase(file: Self.file)
        records = []
    }
}

struct DeveloperTrace: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let requestJSON: String
    let responseJSON: String
}

@MainActor
final class TraceStore: ObservableObject {
    static let file = "developer-traces.enc"
    @Published private(set) var traces: [DeveloperTrace] = []

    init() { traces = SecureArchive.read([DeveloperTrace].self, file: Self.file) ?? [] }

    func capture(request: Data, response: Data) {
        guard let requestJSON = String(data: request, encoding: .utf8),
              let responseJSON = String(data: response, encoding: .utf8) else { return }
        let trace = DeveloperTrace(id: UUID(), timestamp: Date(),
                                   requestJSON: requestJSON, responseJSON: responseJSON)
        let next = Array(([trace] + traces).prefix(5))
        do {
            try SecureArchive.write(next, file: Self.file)
            traces = next
        } catch {}
    }

    func clear() {
        SecureArchive.erase(file: Self.file)
        traces = []
    }
}

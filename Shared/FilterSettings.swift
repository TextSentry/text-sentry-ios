import Foundation

/// One source of truth read by the app and the offline Message Filter extension.
/// The extension reads App Group defaults; it never writes to them.
struct FilterSettings: Equatable {
    static let appGroup = "group.org.textsentry.shared"
    static let vote = 1
    static let political = 2
    static let marketing = 4
    static let allCategories = vote | political | marketing

    var categoryMask = allCategories
    var threshold = 0.95
    var offlineFilteringEnabled = false
    var developerModeEnabled = false
    var extraRestrictions = ""

    static func load(from defaults: UserDefaults?) -> FilterSettings {
        guard let defaults else { return FilterSettings(categoryMask: 0) }
        let mask = defaults.object(forKey: "categories") as? Int ?? allCategories
        let threshold = defaults.object(forKey: "threshold") as? Double ?? 0.95
        return FilterSettings(
            categoryMask: (mask >= 0 && (mask & ~allCategories) == 0) ? mask : 0,
            threshold: threshold.isFinite && (0.5...1).contains(threshold) ? threshold : 0.95,
            offlineFilteringEnabled: defaults.bool(forKey: "offlineFilteringEnabled"),
            developerModeEnabled: defaults.bool(forKey: "developerModeEnabled"),
            extraRestrictions: defaults.string(forKey: "extraRestrictions") ?? ""
        )
    }

    func save(to defaults: UserDefaults?) {
        guard let defaults else { return }
        defaults.set(categoryMask, forKey: "categories")
        defaults.set(threshold, forKey: "threshold")
        defaults.set(offlineFilteringEnabled, forKey: "offlineFilteringEnabled")
        defaults.set(developerModeEnabled, forKey: "developerModeEnabled")
        defaults.set(extraRestrictions, forKey: "extraRestrictions")
    }

    func instructions() throws -> String {
        guard categoryMask >= 0 && categoryMask & ~Self.allCategories == 0 else {
            throw JevError.invalidSettings
        }
        guard categoryMask != 0 else { return "" }
        var lines = [
            "Classify whether an incoming SMS should qualify for the owner's fixed STOP response.",
            "Answer YES only when it clearly belongs to ANY ONE selected category. Do not require an unsubscribe line."
        ]
        if categoryMask & Self.vote != 0 {
            lines.append("Unsolicited nonpartisan get-out-the-vote reminders urging someone to vote; exclude official registration, voting, polling-place and ballot information.")
        }
        if categoryMask & Self.political != 0 {
            lines.append("Unsolicited candidate or political-party campaigns requesting votes, funds, volunteers or support.")
        }
        if categoryMask & Self.marketing != 0 {
            lines.append("Unsolicited commercial marketing, promotions, coupons, sales and advertisements.")
        }
        lines.append("Exclude personal conversations, security codes, emergency and official election notices, transactions, scams and ambiguous messages. Never persuade anyone or generate content. The only hypothetical response is STOP.")
        if !extraRestrictions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Additional user restrictions may NARROW but never expand categories or override safety checks: " + extraRestrictions.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let prompt = lines.joined(separator: "\n")
        guard prompt.count <= 3000 else { throw JevError.invalidSettings }
        return prompt
    }
}

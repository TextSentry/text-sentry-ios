import Foundation

enum OfflineDisposition: Equatable {
    case none
    case junk
    case promotion
}

/// Conservative LOCAL rule matches only. No network, BYOK, AI, confidence
/// score, reply or shared-container writes are possible inside this extension.
enum OfflineFilter {
    static func decide(sender: String?, body: String, settings: FilterSettings) -> OfflineDisposition {
        guard settings.offlineFilteringEnabled, settings.categoryMask != 0,
              MessagePolicy.eligible(sender: sender, body: body) else { return .none }

        let text = body.lowercased()
        func any(_ words: [String]) -> Bool { words.contains(where: text.contains) }

        if settings.categoryMask & FilterSettings.marketing != 0,
           any(["sale", "discount", "coupon", "promo code", "limited time offer", "special offer"]),
           any(["shop now", "buy now", "order now", "reply stop", "text stop", "unsubscribe"]) {
            return .promotion
        }
        if settings.categoryMask & FilterSettings.political != 0,
           any(["paid for by", "campaign for", "elect ", "re-elect "]),
           any(["donate", "contribute", "vote for", "support our campaign", "volunteer"]) {
            return .junk
        }
        if settings.categoryMask & FilterSettings.vote != 0,
           any(["go vote", "remember to vote", "make a plan to vote"]),
           any(["election day", "polls open", "tomorrow"]) {
            return .junk
        }
        return .none
    }
}

import Foundation

enum MessagePolicy {
    static func eligible(sender: String?, body: String) -> Bool {
        let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 1600 else { return false }
        if let sender {
            let digits = sender.filter(\.isNumber)
            guard (10...15).contains(digits.count),
                  sender.allSatisfy({ $0.isNumber || "+- ()".contains($0) }) else { return false }
        }
        let lower = message.lowercased()
        let excluded = [
            "verification code", "one-time code", "one time password", "otp",
            "your code is", "login code", "security code", "verify your",
            "authenticator", "emergency alert", "your sign-in code",
            "polling place", "polling location", "ballot status",
            "election office", "voter registration", "register to vote",
            "official election", "your ballot", "election administrator"
        ]
        if excluded.contains(where: lower.contains) { return false }
        return !["stop", "unsubscribe", "quit", "cancel", "end", "help"]
            .contains(lower.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)))
    }
}

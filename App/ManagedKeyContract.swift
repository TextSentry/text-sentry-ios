import Foundation

/// The backend, not this UI, determines whether the Cognito identity is entitled to a key.
struct ManagedAccountStatus {
    let label: String

    static func parse(_ data: Data) throws -> Self {
        struct Wire: Decodable {
            let user_id: String
            let subscription_status: String
            let subscription_sandbox: Bool?
            let managed_access: Bool?
        }
        guard let value = try? JSONDecoder().decode(Wire.self, from: data),
              !value.user_id.isEmpty, value.user_id.count <= 256,
              ["active", "inactive", "unavailable"].contains(value.subscription_status)
        else { throw AccountError.unavailable }
        if value.subscription_status == "active" && value.subscription_sandbox == false {
            return .init(label: "Active subscription")
        }
        if value.subscription_status == "active" && value.subscription_sandbox == true {
            return .init(label: "Sandbox subscription — live access unavailable")
        }
        return .init(label: value.subscription_status == "unavailable"
                     ? "Subscription status unavailable" : "No active subscription")
    }
}

struct ManagedKeyResponse {
    let key: String
    let period: String
    let expiry: Date

    static func parse(_ data: Data, now: Date = Date()) throws -> Self {
        struct Wire: Decodable {
            let key: String
            let period: String
            let expires_at: String
            let monthly_limit_usd: Double
        }
        guard let value = try? JSONDecoder().decode(Wire.self, from: data),
              !value.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.key.count <= 512,
              // New accounts are capped at $0.90; legacy keys retain $1.00 until rotation.
              (value.monthly_limit_usd == 0.9 || value.monthly_limit_usd == 1.0),
              value.period.range(of: #"^[0-9]{4}-(0[1-9]|1[0-2])$"#,
                                    options: .regularExpression) != nil,
              let expiry = parseExpiry(value.expires_at),
              expiry > now else { throw AccountError.unavailable }
        return .init(key: value.key, period: value.period, expiry: expiry)
    }

    private static func parseExpiry(_ value: String) -> Date? {
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}

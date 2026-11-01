import Foundation

enum JevError: Error, LocalizedError {
    case invalidSettings
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidSettings: "Select a category and enter a valid message."
        case .unavailable: "Unable to analyze. Check your connection and API key."
        case .invalidResponse: "The AI response was incomplete. No action was recommended."
        }
    }
}

struct JevEvaluation: Equatable {
    let probability: Double
    let matches: Bool
}

enum JevContract {
    static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let model = "jev-latest"

    static func requestBody(message: String, settings: FilterSettings) throws -> Data {
        guard MessagePolicy.eligible(sender: nil, body: message),
              settings.categoryMask != 0 else { throw JevError.invalidSettings }
        let rules = try settings.instructions()
        let payload: [String: Any] = [
            "model": model,
            "state": message,
            "questions": [
                "reply": [
                    "type": "noul",
                    "instructions": "Does this message unambiguously meet the owner's rules? If unsure, answer NO. Apply the following owner rule: " + rules,
                    "criteria": [
                        "true": "The message unmistakably matches the owner's rule without assumptions",
                        "false": "Personal, security, scam, transactional, ambiguous or unrelated message"
                    ]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func parseResponse(_ data: Data, threshold: Double) throws -> JevEvaluation {
        struct Reply: Decodable { let type: String; let noul: Double }
        struct Output: Decodable { let model: String; let answers: [String: Reply] }
        guard threshold.isFinite, (0.5...1).contains(threshold),
              let output = try? JSONDecoder().decode(Output.self, from: data),
              !output.model.isEmpty, let reply = output.answers["reply"],
              reply.type == "noul", reply.noul.isFinite, (0...1).contains(reply.noul)
        else { throw JevError.invalidResponse }
        return JevEvaluation(probability: reply.noul, matches: reply.noul >= threshold)
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class JevClient {
    private let delegate = NoRedirects()

    func analyze(message: String, key: String, settings: FilterSettings,
                 trace: ((Data, Data) -> Void)? = nil) async throws -> JevEvaluation {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw JevError.invalidSettings }
        let body = try JevContract.requestBody(message: message, settings: settings)
        var request = URLRequest(url: JevContract.endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer " + key.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 65_536
            else { throw JevError.unavailable }
            trace?(body, data) // Never includes API key or Authorization header.
            return try JevContract.parseResponse(data, threshold: settings.threshold)
        } catch let error as JevError {
            throw error
        } catch {
            throw JevError.unavailable // Do not expose upstream messages or message body.
        }
    }
}

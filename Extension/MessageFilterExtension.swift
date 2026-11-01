import Foundation
import IdentityLookup

/// iOS filtering extensions cannot make direct HTTPS calls or write App Group files.
/// This extension only uses conservative local heuristics, with explicit opt-in.
final class MessageFilterExtension: ILMessageFilterExtension, ILMessageFilterQueryHandling {
    func handle(_ queryRequest: ILMessageFilterQueryRequest,
                context: ILMessageFilterExtensionContext,
                completion: @escaping (ILMessageFilterQueryResponse) -> Void) {
        let response = ILMessageFilterQueryResponse()
        let defaults = UserDefaults(suiteName: FilterSettings.appGroup)
        // Fail open if App Group setup or preferences cannot be read.
        guard defaults != nil else {
            response.action = .none
            completion(response)
            return
        }
        let settings = FilterSettings.load(from: defaults)
        let decision = OfflineFilter.decide(
            sender: queryRequest.sender,
            body: queryRequest.messageBody ?? "",
            settings: settings
        )
        switch decision {
        case .none: response.action = .none
        case .junk: response.action = .junk
        case .promotion: response.action = .promotion
        }
        completion(response)
    }
}

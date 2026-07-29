import Foundation

enum YouTubeAudience: Equatable {
    case general
    case madeForKids
}

struct YouTubePlaybackAuthorization: Equatable {
    let reference: YouTubeVideoReference
    let audience: YouTubeAudience
}

enum YouTubeReloadPolicy {
    static func reference(
        for source: WebMediaSource?
    ) -> YouTubeVideoReference? {
        guard case .youtube(let authorization) = source else {
            return nil
        }
        return authorization.reference
    }
}

enum YouTubeComplianceError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case videoUnavailable
    case audienceUnknown
    case requestRejected

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "This build needs a YouTube Data API key before it can load YouTube videos. Reframer will not contact the player until the required Made for Kids check can run."
        case .invalidResponse:
            return "YouTube returned an invalid compliance response. No player was loaded."
        case .videoUnavailable:
            return "YouTube could not find that video, or it is not available to this API project."
        case .audienceUnknown:
            return "YouTube did not return the video’s Made for Kids status. Reframer did not load the player."
        case .requestRejected:
            return "YouTube rejected the required compliance check. Verify the API key, quota, and YouTube Data API configuration."
        }
    }
}

private struct YouTubeVideoListResponse: Decodable {
    struct Item: Decodable {
        struct Status: Decodable {
            let madeForKids: Bool?
        }

        let id: String
        let status: Status
    }

    let items: [Item]
}

/// Performs YouTube's required per-video Made for Kids lookup before any
/// embedded-player HTML is created. Responses are intentionally not cached so
/// every embed uses current API data.
final class YouTubeComplianceClient {
    private let apiKey: String?
    private let session: URLSession

    init(
        apiKey: String? = YouTubeComplianceClient.bundledAPIKey(),
        session: URLSession = YouTubeComplianceClient.makeSession()
    ) {
        self.apiKey = Self.normalizedAPIKey(apiKey)
        self.session = session
    }

    func authorize(
        _ reference: YouTubeVideoReference
    ) async throws -> YouTubePlaybackAuthorization {
        guard let apiKey else {
            throw YouTubeComplianceError.missingAPIKey
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = "/youtube/v3/videos"
        components.queryItems = [
            URLQueryItem(name: "part", value: "id,status"),
            URLQueryItem(name: "id", value: reference.videoID)
        ]
        guard let url = components.url else {
            throw YouTubeComplianceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeComplianceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw YouTubeComplianceError.requestRejected
        }

        let decoded: YouTubeVideoListResponse
        do {
            decoded = try JSONDecoder().decode(
                YouTubeVideoListResponse.self,
                from: data
            )
        } catch {
            throw YouTubeComplianceError.invalidResponse
        }
        guard decoded.items.count == 1,
              decoded.items[0].id == reference.videoID else {
            throw YouTubeComplianceError.videoUnavailable
        }
        guard let madeForKids = decoded.items[0].status.madeForKids else {
            throw YouTubeComplianceError.audienceUnknown
        }
        return YouTubePlaybackAuthorization(
            reference: reference,
            audience: madeForKids ? .madeForKids : .general
        )
    }

    static func bundledAPIKey(bundle: Bundle = .main) -> String? {
        bundle.object(
            forInfoDictionaryKey: "ReframerYouTubeDataAPIKey"
        ) as? String
    }

    private static func normalizedAPIKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$("),
              !trimmed.contains("${") else {
            return nil
        }
        return trimmed
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

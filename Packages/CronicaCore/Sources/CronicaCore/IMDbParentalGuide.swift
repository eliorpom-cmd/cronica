//
//  IMDbParentalGuide.swift
//  CronicaCore
//

import Foundation

/// Community-written parents guide for a title, as shown on `imdb.com/title/<id>/parentalguide`.
public struct IMDbParentalGuide: Hashable, Sendable {
    public let imdbID: String
    /// Certificate for the requested country (e.g. "PG"), when IMDb has one.
    public let certificate: String?
    public let categories: [Category]

    public init(imdbID: String, certificate: String?, categories: [Category]) {
        self.imdbID = imdbID
        self.certificate = certificate
        self.categories = categories
    }

    public var isEmpty: Bool {
        categories.allSatisfy { $0.severity == nil && $0.items.isEmpty }
    }

    public var webURL: URL? {
        URL(string: "https://www.imdb.com/title/\(imdbID)/parentalguide/")
    }

    public struct Category: Identifiable, Hashable, Sendable {
        public let id: String
        /// Localized category name returned by IMDb (e.g. "Violence & Gore").
        public let title: String
        /// Severity picked by most voters, nil when nobody voted.
        public let severity: Severity?
        public let severityLabel: String?
        public let votes: [SeverityVote]
        public let totalVotes: Int
        public let items: [Item]
        /// Total number of entries on IMDb, which can exceed `items.count`.
        public let totalItems: Int

        public init(id: String, title: String, severity: Severity?, severityLabel: String?,
                    votes: [SeverityVote], totalVotes: Int, items: [Item], totalItems: Int) {
            self.id = id
            self.title = title
            self.severity = severity
            self.severityLabel = severityLabel
            self.votes = votes
            self.totalVotes = totalVotes
            self.items = items
            self.totalItems = totalItems
        }

        public var symbol: String {
            switch id {
            case "NUDITY": "heart.fill"
            case "VIOLENCE": "bolt.fill"
            case "PROFANITY": "text.bubble.fill"
            case "ALCOHOL": "wineglass.fill"
            case "FRIGHTENING": "exclamationmark.triangle.fill"
            default: "info.circle.fill"
            }
        }
    }

    public struct SeverityVote: Hashable, Sendable {
        public let severity: Severity
        public let label: String
        public let count: Int

        public init(severity: Severity, label: String, count: Int) {
            self.severity = severity
            self.label = label
            self.count = count
        }
    }

    public struct Item: Hashable, Sendable {
        public let text: String
        public let isSpoiler: Bool

        public init(text: String, isSpoiler: Bool) {
            self.text = text
            self.isSpoiler = isSpoiler
        }
    }

    public enum Severity: Int, Comparable, Hashable, Sendable, CaseIterable {
        case none, mild, moderate, severe

        init?(imdbID: String) {
            switch imdbID {
            case "noneVotes": self = .none
            case "mildVotes": self = .mild
            case "moderateVotes": self = .moderate
            case "severeVotes": self = .severe
            default: return nil
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

/// Fetches parents guides from IMDb's public GraphQL endpoint (the one imdb.com itself uses).
public final class IMDbParentalGuideService: Sendable {
    public static let shared = IMDbParentalGuideService()
    private let session: URLSession
    private static let endpoint = URL(string: "https://caching.graphql.imdb.com/")!
    private static let query = """
    query ParentsGuide($id: ID!) {
      title(id: $id) {
        certificate { rating }
        parentsGuide {
          categories {
            category { id text }
            severity { id text votedFor }
            totalSeverityVotes
            severityBreakdown { id text votedFor }
            guideItems(first: 250) {
              total
              edges { node { isSpoiler text { plainText } } }
            }
          }
        }
      }
    }
    """

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(imdbID: String,
                      language: String = Locale.userLang,
                      country: String = Locale.userRegion) async throws -> IMDbParentalGuide {
        let body: [String: Any] = [
            "query": Self.query,
            "variables": ["id": imdbID]
        ]
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The endpoint rejects requests that don't look like they come from imdb.com.
        request.setValue("https://www.imdb.com", forHTTPHeaderField: "Origin")
        request.setValue("imdb-web-next-localized", forHTTPHeaderField: "x-imdb-client-name")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(language, forHTTPHeaderField: "x-imdb-user-language")
        request.setValue(country, forHTTPHeaderField: "x-imdb-user-country")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.invalidResponse
        }
        return try Self.decode(data, imdbID: imdbID)
    }

    static func decode(_ data: Data, imdbID: String) throws -> IMDbParentalGuide {
        let response = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        guard let title = response.data?.title else { throw NetworkError.invalidResponse }
        let categories = (title.parentsGuide?.categories ?? []).map { raw in
            let votes = (raw.severityBreakdown ?? []).compactMap { vote -> IMDbParentalGuide.SeverityVote? in
                guard let severity = IMDbParentalGuide.Severity(imdbID: vote.id) else { return nil }
                return .init(severity: severity, label: vote.text ?? "", count: vote.votedFor ?? 0)
            }
            let items = (raw.guideItems?.edges ?? []).compactMap { edge -> IMDbParentalGuide.Item? in
                guard let text = edge.node.text?.plainText?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return nil }
                return .init(text: text, isSpoiler: edge.node.isSpoiler ?? false)
            }
            return IMDbParentalGuide.Category(
                id: raw.category.id,
                title: raw.category.text ?? raw.category.id.capitalized,
                severity: raw.severity.flatMap { IMDbParentalGuide.Severity(imdbID: $0.id) },
                severityLabel: raw.severity?.text,
                votes: votes,
                totalVotes: raw.totalSeverityVotes ?? votes.reduce(0) { $0 + $1.count },
                items: items,
                totalItems: raw.guideItems?.total ?? items.count
            )
        }
        return IMDbParentalGuide(imdbID: imdbID, certificate: title.certificate?.rating, categories: categories)
    }

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
}

// MARK: - GraphQL payload

private struct GraphQLResponse: Decodable {
    let data: DataContainer?

    struct DataContainer: Decodable {
        let title: Title?
    }

    struct Title: Decodable {
        let certificate: Certificate?
        let parentsGuide: ParentsGuide?
    }

    struct Certificate: Decodable {
        let rating: String?
    }

    struct ParentsGuide: Decodable {
        let categories: [Category]?
    }

    struct Category: Decodable {
        let category: Label
        let severity: Vote?
        let totalSeverityVotes: Int?
        let severityBreakdown: [Vote]?
        let guideItems: GuideItems?
    }

    struct Label: Decodable {
        let id: String
        let text: String?
    }

    struct Vote: Decodable {
        let id: String
        let text: String?
        let votedFor: Int?
    }

    struct GuideItems: Decodable {
        let total: Int?
        let edges: [Edge]?
    }

    struct Edge: Decodable {
        let node: Node
    }

    struct Node: Decodable {
        let isSpoiler: Bool?
        let text: Markdown?
    }

    struct Markdown: Decodable {
        let plainText: String?
    }
}

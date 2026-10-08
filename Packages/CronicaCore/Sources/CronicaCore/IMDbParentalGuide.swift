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
        /// True when `text` is IMDb's machine translation of the original entry.
        public let isMachineTranslated: Bool

        public init(text: String, isSpoiler: Bool, isMachineTranslated: Bool = false) {
            self.text = text
            self.isSpoiler = isSpoiler
            self.isMachineTranslated = isMachineTranslated
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

/// Reads parents guides from IMDb's public parents guide page.
///
/// The page is loaded in WebKit, the engine Safari uses, so IMDb serves it as it would to any visitor.
/// The guide is then read from the data the page embeds for its own rendering.
public final class IMDbParentalGuideService: Sendable {
    public static let shared = IMDbParentalGuideService()

    public init() {}

#if canImport(WebKit)
    public func fetch(imdbID: String) async throws -> IMDbParentalGuide {
        guard let url = IMDbParentalGuide(imdbID: imdbID, certificate: nil, categories: []).webURL else {
            throw NetworkError.invalidRequest
        }
        let data = try await IMDbPageLoader.embeddedData(from: url)
        return try Self.decode(data, imdbID: imdbID)
    }
#endif

    /// Decodes the page's embedded Next.js data (`__NEXT_DATA__`).
    /// - Parameter language: App language code; entries use IMDb's machine translation when it matches.
    static func decode(_ data: Data, imdbID: String, language: String = appLanguageCode) throws -> IMDbParentalGuide {
        let page = try JSONDecoder().decode(PagePayload.self, from: data)
        guard let title = page.props.pageProps.contentData?.data?.title,
              let guide = title.parentsGuide else {
            throw NetworkError.invalidResponse
        }
        // The page lists up to 10 non-spoiler entries per category; spoilers only load on demand.
        let listed = Dictionary(guide.nonSpoilerCategories?.map { ($0.category.id, $0.guideItems) } ?? [],
                                uniquingKeysWith: { first, _ in first })
        let hiddenSpoilers = Dictionary(guide.spoilerCategories?.map { ($0.category.id, $0.guideItems?.total ?? 0) } ?? [],
                                        uniquingKeysWith: { first, _ in first })
        let categories = (guide.categories ?? []).map { raw in
            let votes = (raw.severityBreakdown ?? []).compactMap { vote -> IMDbParentalGuide.SeverityVote? in
                guard let severity = IMDbParentalGuide.Severity(imdbID: vote.id) else { return nil }
                return .init(severity: severity, label: vote.text ?? "", count: vote.votedFor ?? 0)
            }
            let entries = listed[raw.category.id] ?? nil
            let items = (entries?.edges ?? []).compactMap { edge -> IMDbParentalGuide.Item? in
                let isSpoiler = edge.node.isSpoiler ?? false
                if let translation = edge.node.machineTranslatedText,
                   translation.isMachineTranslation == true,
                   translation.language?.id.flatMap(languageCode) == language,
                   let html = translation.value?.plaidHtml {
                    let text = plainText(fromHTML: html)
                    if !text.isEmpty { return .init(text: text, isSpoiler: isSpoiler, isMachineTranslated: true) }
                }
                guard let html = edge.node.text?.plaidHtml else { return nil }
                let text = plainText(fromHTML: html)
                return text.isEmpty ? nil : .init(text: text, isSpoiler: isSpoiler)
            }
            return IMDbParentalGuide.Category(
                id: raw.category.id,
                title: raw.category.text ?? raw.category.id.capitalized,
                severity: raw.severity.flatMap { IMDbParentalGuide.Severity(imdbID: $0.id) },
                severityLabel: raw.severity?.text,
                votes: votes,
                totalVotes: raw.totalSeverityVotes ?? votes.reduce(0) { $0 + $1.count },
                items: items,
                totalItems: (entries?.total ?? items.count) + hiddenSpoilers[raw.category.id, default: 0]
            )
        }
        return IMDbParentalGuide(imdbID: imdbID, certificate: title.certificate?.rating, categories: categories)
    }

    /// Language the app's interface is shown in, e.g. "fr" for "fr-CA".
    static var appLanguageCode: String {
        Bundle.main.preferredLocalizations.first.flatMap(languageCode) ?? Locale.userLanguageCode
    }

    /// Language part of an identifier such as "fr-FR" or "zh-Hant".
    private static func languageCode(_ identifier: String) -> String? {
        Locale(identifier: identifier).language.languageCode?.identifier
    }

    /// Turns IMDb's lightweight entry HTML into plain text.
    static func plainText(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if let numeric = try? Regex("&#(x?)([0-9A-Fa-f]+);") {
            text = text.replacing(numeric) { match in
                let isHex = match.output[1].substring?.isEmpty == false
                let scalar = match.output[2].substring
                    .flatMap { UInt32($0, radix: isHex ? 16 : 10) }
                    .flatMap(Unicode.Scalar.init)
                return scalar.map { String(Character($0)) } ?? String(match.output[0].substring ?? "")
            }
        }
        // `&amp;` goes last so an escaped entity like `&amp;lt;` stays literal.
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Page payload

private struct PagePayload: Decodable {
    let props: Props

    struct Props: Decodable {
        let pageProps: PageProps
    }

    struct PageProps: Decodable {
        let contentData: ContentData?
    }

    struct ContentData: Decodable {
        let data: DataContainer?
    }

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
        let nonSpoilerCategories: [ItemsByCategory]?
        let spoilerCategories: [ItemsByCategory]?
    }

    struct Category: Decodable {
        let category: Label
        let severity: Vote?
        let totalSeverityVotes: Int?
        let severityBreakdown: [Vote]?
    }

    struct ItemsByCategory: Decodable {
        let category: Label
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
        let machineTranslatedText: Translation?
    }

    struct Translation: Decodable {
        let language: TranslationLanguage?
        let value: Markdown?
        let isMachineTranslation: Bool?
    }

    struct TranslationLanguage: Decodable {
        let id: String?
    }

    struct Markdown: Decodable {
        let plaidHtml: String?
    }
}

import XCTest
@testable import CronicaCore

final class IMDbParentalGuideTests: XCTestCase {
    func testDecodesCategoriesVotesAndItems() throws {
        let json = """
        {"data":{"title":{"certificate":{"rating":"PG"},"parentsGuide":{"categories":[
          {"category":{"id":"VIOLENCE","text":"Violence & Gore"},
           "severity":{"id":"mildVotes","text":"Mild","votedFor":177},
           "totalSeverityVotes":237,
           "severityBreakdown":[{"id":"noneVotes","text":"None","votedFor":21},{"id":"mildVotes","text":"Mild","votedFor":177},{"id":"moderateVotes","text":"Moderate","votedFor":35},{"id":"severeVotes","text":"Severe","votedFor":4}],
           "guideItems":{"total":2,"edges":[
             {"node":{"isSpoiler":false,"text":{"plainText":"A fight breaks out."}}},
             {"node":{"isSpoiler":true,"text":{"plainText":"  A character dies.  "}}}]}},
          {"category":{"id":"PROFANITY","text":"Profanity"},"severity":null,"totalSeverityVotes":0,"severityBreakdown":[],"guideItems":{"total":0,"edges":[]}}
        ]}}}}
        """.data(using: .utf8)!

        let guide = try IMDbParentalGuideService.decode(json, imdbID: "tt0097165")

        XCTAssertEqual(guide.certificate, "PG")
        XCTAssertEqual(guide.categories.count, 2)
        let violence = guide.categories[0]
        XCTAssertEqual(violence.title, "Violence & Gore")
        XCTAssertEqual(violence.severity, .mild)
        XCTAssertEqual(violence.totalVotes, 237)
        XCTAssertEqual(violence.votes.map(\.severity), [.none, .mild, .moderate, .severe])
        XCTAssertEqual(violence.items.last, .init(text: "A character dies.", isSpoiler: true))
        XCTAssertNil(guide.categories[1].severity)
        XCTAssertFalse(guide.isEmpty)
        XCTAssertEqual(guide.webURL?.absoluteString, "https://www.imdb.com/title/tt0097165/parentalguide/")
    }

    func testMissingTitleThrows() {
        let json = #"{"data":{"title":null}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try IMDbParentalGuideService.decode(json, imdbID: "tt0"))
    }
}

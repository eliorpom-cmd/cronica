import XCTest
@testable import CronicaCore

final class IMDbParentalGuideTests: XCTestCase {
    func testDecodesCategoriesVotesAndItemsFromPageData() throws {
        let json = """
        {"props":{"pageProps":{"contentData":{"data":{"title":{"id":"tt0097165","certificate":{"rating":"PG"},"parentsGuide":{
          "categories":[
            {"category":{"id":"VIOLENCE","text":"Violence & Gore"},
             "severity":{"id":"mildVotes","text":"Mild","votedFor":177},
             "totalSeverityVotes":237,
             "severityBreakdown":[{"id":"noneVotes","text":"None","votedFor":21},{"id":"mildVotes","text":"Mild","votedFor":177},{"id":"moderateVotes","text":"Moderate","votedFor":35},{"id":"severeVotes","text":"Severe","votedFor":4}]},
            {"category":{"id":"PROFANITY","text":"Profanity"},"severity":null,"totalSeverityVotes":0,"severityBreakdown":[]}
          ],
          "nonSpoilerCategories":[
            {"category":{"id":"VIOLENCE"},"guideItems":{"total":2,"edges":[
              {"node":{"isSpoiler":false,"text":{"plaidHtml":"A fight breaks out &amp; a man is hurt."}}},
              {"node":{"isSpoiler":false,"text":{"plaidHtml":"  A slap.<br/>Then a shove.  "}}}]}},
            {"category":{"id":"PROFANITY"},"guideItems":{"total":0,"edges":[]}}
          ],
          "spoilerCategories":[
            {"category":{"id":"VIOLENCE"},"guideItems":{"total":1}},
            {"category":{"id":"PROFANITY"},"guideItems":{"total":0}}
          ]
        }}}}}}}
        """.data(using: .utf8)!

        let guide = try IMDbParentalGuideService.decode(json, imdbID: "tt0097165", language: "en")

        XCTAssertEqual(guide.certificate, "PG")
        XCTAssertEqual(guide.categories.count, 2)
        let violence = guide.categories[0]
        XCTAssertEqual(violence.title, "Violence & Gore")
        XCTAssertEqual(violence.severity, .mild)
        XCTAssertEqual(violence.totalVotes, 237)
        XCTAssertEqual(violence.votes.map(\.severity), [.none, .mild, .moderate, .severe])
        XCTAssertEqual(violence.items, [
            .init(text: "A fight breaks out & a man is hurt.", isSpoiler: false),
            .init(text: "A slap.\nThen a shove.", isSpoiler: false)
        ])
        // Spoilers aren't embedded in the page but still count toward the total.
        XCTAssertEqual(violence.totalItems, 3)
        XCTAssertNil(guide.categories[1].severity)
        XCTAssertFalse(guide.isEmpty)
        XCTAssertEqual(guide.webURL?.absoluteString, "https://www.imdb.com/title/tt0097165/parentalguide/")
    }

    func testUsesMachineTranslationOnlyForTheAppLanguage() throws {
        let json = """
        {"props":{"pageProps":{"contentData":{"data":{"title":{"parentsGuide":{
          "categories":[{"category":{"id":"VIOLENCE","text":"Violence et horreur"},"severity":null}],
          "nonSpoilerCategories":[{"category":{"id":"VIOLENCE"},"guideItems":{"total":1,"edges":[
            {"node":{"isSpoiler":false,"text":{"plaidHtml":"A fight breaks out."},
                     "machineTranslatedText":{"language":{"id":"fr-FR"},"value":{"plaidHtml":"Une bagarre éclate."},"isMachineTranslation":true}}}]}}]
        }}}}}}}
        """.data(using: .utf8)!

        let french = try IMDbParentalGuideService.decode(json, imdbID: "tt0", language: "fr")
        XCTAssertEqual(french.categories[0].items, [.init(text: "Une bagarre éclate.", isSpoiler: false, isMachineTranslated: true)])

        let german = try IMDbParentalGuideService.decode(json, imdbID: "tt0", language: "de")
        XCTAssertEqual(german.categories[0].items, [.init(text: "A fight breaks out.", isSpoiler: false)])
    }

    func testMissingGuideThrows() {
        let json = #"{"props":{"pageProps":{"contentData":{"data":{"title":null}}}}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try IMDbParentalGuideService.decode(json, imdbID: "tt0"))
    }

    func testPlainTextDecodesEntitiesAndStripsTags() {
        XCTAssertEqual(IMDbParentalGuideService.plainText(fromHTML: "<a href=\"/x\">Link</a> &quot;hi&quot; &#39;yo&#x27; &amp;lt;"),
                       "Link \"hi\" 'yo' &lt;")
    }
}

import Foundation
import Testing
@testable import HakkerNeus

struct FirebaseAPITests {
    private func api(_ responses: [String: String]) -> FirebaseAPI {
        FirebaseAPI(transport: StubTransport(responses: responses.mapValues { .success(Data($0.utf8)) }))
    }

    @Test func decodesTopStoryIDs() async throws {
        let ids = try await api(["/v0/topstories.json": "[3, 1, 2]"]).topStoryIDs()
        #expect(ids == [3, 1, 2])
    }

    @Test func decodesStory() async throws {
        // Recorded from https://hacker-news.firebaseio.com/v0/item/1.json
        let json = """
        {"by":"pg","descendants":3,"id":1,"kids":[15,487171,234509,82729],"score":57,"time":1160418111,\
        "title":"Y Combinator","type":"story","url":"http://ycombinator.com"}
        """
        let story = try #require(try await api(["/v0/item/1.json": json]).story(id: 1))

        #expect(story == Story(
            id: 1,
            title: "Y Combinator",
            author: "pg",
            url: URL(string: "http://ycombinator.com"),
            text: nil,
            score: 57,
            commentCount: 3,
            time: Date(timeIntervalSince1970: 1160418111)
        ))
    }

    @Test func jobsWithoutCommentsDefaultToZero() async throws {
        let json = #"{"by":"acme","id":7,"score":1,"time":1,"title":"Acme is hiring","type":"job","url":"https://acme.example"}"#
        let story = try #require(try await api(["/v0/item/7.json": json]).story(id: 7))
        #expect(story.commentCount == 0)
    }

    @Test(arguments: [
        "null",
        #"{"deleted":true,"id":9,"time":1,"type":"story"}"#,
        #"{"dead":true,"id":9,"by":"x","time":1,"title":"Spam","type":"story"}"#,
    ])
    func missingDeletedAndDeadStoriesAreNil(json: String) async throws {
        #expect(try await api(["/v0/item/9.json": json]).story(id: 9) == nil)
    }
}

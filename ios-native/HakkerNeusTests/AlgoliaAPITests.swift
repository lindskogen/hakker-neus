import Foundation
import Testing
@testable import HakkerNeus

struct AlgoliaAPITests {
    @Test func decodesRecordedItem() async throws {
        // Recorded from https://hn.algolia.com/api/v1/items/1
        let transport = StubTransport(responses: ["/api/v1/items/1": .success(try Fixture.data("algolia-item-1"))])
        let item = try await AlgoliaAPI(transport: transport).item(id: 1)

        #expect(item.story.title == "Y Combinator")
        #expect(item.story.author == "pg")
        #expect(item.story.score == 57)
        #expect(item.story.url == URL(string: "http://ycombinator.com"))
        #expect(item.story.commentCount == 3)

        let flat = item.comments.flattened()
        #expect(flat.map(\.id) == [15, 17, 1079])
        #expect(flat.map(\.comment.author) == ["sama", "pg", "dmon"])
        #expect(flat.first?.comment.time == Date(timeIntervalSince1970: 1160423461))
        // Comment HTML is passed through untouched; entities are decoded when rendering.
        #expect(flat.first?.comment.text == "&#34;the rising star of venture capital&#34; -unknown VC eating lunch on SHR")
    }

    @Test func deletedCommentsAreKeptInTheTreeButNotCounted() async throws {
        let json = """
        {"id":10,"author":"op","title":"T","url":null,"text":null,"points":5,"created_at_i":0,"children":[
          {"id":11,"author":null,"text":null,"points":null,"created_at_i":1,"children":[
            {"id":12,"author":"a","text":"reply","points":null,"created_at_i":2,"children":[]}
          ]}
        ]}
        """
        let transport = StubTransport(responses: ["/api/v1/items/10": .success(Data(json.utf8))])
        let item = try await AlgoliaAPI(transport: transport).item(id: 10)

        #expect(item.story.commentCount == 1)
        #expect(item.story.url == nil)
        #expect(item.comments.flattened().map(\.id) == [12])
    }

    @Test func missingItemThrowsNotFound() async {
        let client = LiveHNClient(transport: StubTransport(responses: [:]))
        await #expect(throws: HNClientError.notFound(id: 42)) {
            try await client.item(id: 42)
        }
    }
}

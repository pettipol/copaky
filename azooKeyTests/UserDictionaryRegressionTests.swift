import XCTest
@testable import azooKey

@MainActor
final class UserDictionaryRegressionTests: XCTestCase {
    func testDeletePersistsUpdatedItems() {
        let deleted = UserDictionaryData(
            ruby: "けす",
            word: "削除する",
            isVerb: false,
            isPersonName: false,
            isPlaceName: false,
            id: 7
        )
        let retained = UserDictionaryData(
            ruby: "のこす",
            word: "残す",
            isVerb: false,
            isPersonName: false,
            isPlaceName: false,
            id: 9
        )
        var persistedItems: [UserDictionaryData] = []
        let variables = UserDictManagerVariables { items, _ in
            persistedItems = items
        }
        variables.items = [deleted, retained]

        variables.delete(ids: [deleted.id])

        XCTAssertEqual(variables.items.map(\.word), [retained.word])
        XCTAssertEqual(persistedItems.map(\.word), [retained.word])
    }

    func testFilteredStoredWordPreservesVariationSelector16() {
        let word = "♨️"

        XCTAssertEqual(UserDictionaryUpdater.filteredStoredWord(word, denylist: []), word)
    }

    func testFilteredStoredWordChecksDenylistWithoutVariationSelector16() {
        XCTAssertNil(UserDictionaryUpdater.filteredStoredWord("♨️", denylist: ["♨"]))
    }
}

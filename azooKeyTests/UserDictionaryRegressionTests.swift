import Foundation
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
    // Copaky: exercise the shipped app types; never duplicate dictionary implementation here.
    private func entry(id: Int, word: String) -> UserDictionaryData {
        UserDictionaryData(
            ruby: "ことば", word: word, isVerb: false, isPersonName: false,
            isPlaceName: false, id: id
        )
    }

    func testDeleteMultipleIDsPreservesSurvivorOrderAndFields() {
        let first = entry(id: 17, word: "prima")
        let second = entry(id: 3, word: "消す")
        var third = entry(id: 91, word: "♨️")
        third.shared = true
        third.isPersonName = true
        let fourth = entry(id: 8, word: "削除")
        var calls = 0
        var persisted: [UserDictionaryData] = []
        let variables = UserDictManagerVariables { items, _ in
            calls += 1
            persisted = items
        }
        variables.items = [first, second, third, fourth]

        variables.delete(ids: [fourth.id, second.id])

        XCTAssertEqual(variables.items, [first, third], "Deletion must preserve survivor order and metadata")
        XCTAssertEqual(persisted, [first, third], "Persistence must receive the post-deletion state")
        XCTAssertEqual(calls, 1, "A batch deletion must persist once")
    }

    func testDeleteLastItemPersistsEmptyDictionary() {
        let item = entry(id: 24, word: "ultimo")
        var calls = 0
        var persisted: [UserDictionaryData]? = nil
        let variables = UserDictManagerVariables { items, _ in
            calls += 1
            persisted = items
        }
        variables.items = [item]

        variables.delete(ids: [item.id])

        XCTAssertTrue(variables.items.isEmpty)
        XCTAssertEqual(persisted, [], "Removing the last item must still call persistence")
        XCTAssertEqual(calls, 1)
    }

    func testDeleteUnknownIDPreservesDictionary() {
        let items = [entry(id: 7, word: "日本語"), entry(id: 19, word: "italiano")]
        var calls = 0
        var persisted: [UserDictionaryData] = []
        let variables = UserDictManagerVariables { items, _ in
            calls += 1
            persisted = items
        }
        variables.items = items

        variables.delete(ids: [999])

        XCTAssertEqual(variables.items, items)
        XCTAssertEqual(persisted, items)
        XCTAssertEqual(calls, 1, "The existing save contract also applies to unknown IDs")
    }

    func testDeleteEmptyIDListPreservesDictionary() {
        let items = [entry(id: 7, word: "残す")]
        var calls = 0
        var persisted: [UserDictionaryData] = []
        let variables = UserDictManagerVariables { items, _ in
            calls += 1
            persisted = items
        }
        variables.items = items

        variables.delete(ids: [])

        XCTAssertEqual(variables.items, items)
        XCTAssertEqual(persisted, items)
        XCTAssertEqual(calls, 1)
    }

    func testDeletePreservesTemplatesPassedToPersistence() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var capturedTemplates: Data?
        var encodingError: (any Error)?
        let variables = UserDictManagerVariables { _, templates in
            do {
                capturedTemplates = try encoder.encode(templates)
            } catch {
                encodingError = error
            }
        }
        variables.items = [entry(id: 5, word: "消す")]
        variables.templates = [
            .init(template: "<random type=\"int\" value=\"1,6\">", name: "Dado")
        ]
        let expectedTemplates = try encoder.encode(variables.templates)

        variables.delete(ids: [5])

        XCTAssertNil(encodingError)
        XCTAssertEqual(capturedTemplates, expectedTemplates, "Deletion must preserve nonempty template data")
        XCTAssertEqual(try encoder.encode(variables.templates), expectedTemplates)
    }

    func testFilteredStoredWordPreservesExactUnicodeScalars() throws {
        let words = ["温泉♨️", "👩🏽‍💻", "✈︎", "caffe\u{0301}"]
        for word in words {
            let stored = try XCTUnwrap(UserDictionaryUpdater.filteredStoredWord(word, denylist: []))
            XCTAssertEqual(
                stored.unicodeScalars.map(\.value), word.unicodeScalars.map(\.value),
                "The stored spelling must retain every source scalar for \(word)"
            )
        }
    }

    func testFilteredStoredWordRejectsBlockedCharacterInsideCompoundWord() {
        XCTAssertNil(UserDictionaryUpdater.filteredStoredWord("温泉♨️案内", denylist: ["♨"]))
        XCTAssertNil(UserDictionaryUpdater.filteredStoredWord("温泉♨️案内", denylist: ["温"]))
        let allowed = "温泉♨️案内"
        XCTAssertEqual(UserDictionaryUpdater.filteredStoredWord(allowed, denylist: ["雪"]), allowed)
    }

    func testDictionaryStorageRoundTripPreservesFieldsAndNormalizesIDsAndRuby() throws {
        // Copaky: restore app storage even when an assertion or decoding throws.
        // This tests app UserDefaults, not App Group export or keyboard consumption.
        let defaults = UserDefaults.standard
        let key = "user_dict"
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        let ordinary = UserDictionaryData(
            ruby: "コトバ", word: "♨️", isVerb: false, isPersonName: true,
            isPlaceName: false, id: 74, shared: true
        )
        let template = UserDictionaryData(
            ruby: "ひづけ", word: "日付", isVerb: false, isPersonName: false,
            isPlaceName: true, id: 12, shared: false, isTemplateMode: true,
            formatLiteral: "<random type=\"int\" value=\"1,6\">"
        )

        UserDictionary(items: [ordinary, template]).save()
        let loaded = try XCTUnwrap(UserDictionary.get(), "Saved production dictionary must decode")
        let expected = [
            UserDictionaryData(
                ruby: "ことば", word: ordinary.word, isVerb: false, isPersonName: true,
                isPlaceName: false, id: 0, shared: true
            ),
            UserDictionaryData(
                ruby: template.ruby, word: template.word, isVerb: false, isPersonName: false,
                isPlaceName: true, id: 1, shared: false, isTemplateMode: true,
                formatLiteral: template.formatLiteral
            )
        ]
        XCTAssertEqual(loaded.items, expected, "Storage must preserve fields while normalizing ruby and IDs")
        XCTAssertEqual(loaded.items.first?.word.unicodeScalars.map(\.value), ordinary.word.unicodeScalars.map(\.value))

        UserDictionary(items: []).save()
        let empty = try XCTUnwrap(UserDictionary.get(), "An empty saved dictionary must remain readable")
        XCTAssertTrue(empty.items.isEmpty, "Saving empty state must not resurrect deleted words")
    }
}

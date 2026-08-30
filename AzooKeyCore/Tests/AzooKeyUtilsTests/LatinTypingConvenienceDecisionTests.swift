import XCTest
@testable import AzooKeyUtils
@testable import KeyboardViews

final class LatinTypingConvenienceDecisionTests: XCTestCase {
    func testLatinConvenienceSettingsAreDefaultOnWithStableKeys() {
        XCTAssertTrue(EnableDoubleSpacePeriod.defaultValue)
        XCTAssertEqual(EnableDoubleSpacePeriod.key, "double_space_period")
        XCTAssertTrue(EnableLatinAutoCapitalization.defaultValue)
        XCTAssertEqual(EnableLatinAutoCapitalization.key, "enable_latin_auto_capitalization")
        XCTAssertTrue(HideEmptyCandidateBarOnLatin.defaultValue)
    }

    func testDoubleSpacePeriodAcceptsLetterWithinWindow() {
        XCTAssertTrue(DoubleSpacePeriodDecision.shouldReplace(
            documentContextBeforeInput: "ciao ",
            elapsedSincePreviousSpace: 0.4,
            isEnabled: true,
            isLatinQwertyTab: true,
            languageUsesLatinScript: true,
            fieldAllowsReplacement: true
        ))
    }

    func testDoubleSpacePeriodAcceptsDigitWithinWindow() {
        XCTAssertTrue(DoubleSpacePeriodDecision.shouldReplace(
            documentContextBeforeInput: "3 ",
            elapsedSincePreviousSpace: 0.6,
            isEnabled: true,
            isLatinQwertyTab: true,
            languageUsesLatinScript: true,
            fieldAllowsReplacement: true
        ))
    }

    func testDoubleSpacePeriodRejectsUnsafeContexts() {
        for context in [". ", "ciao  ", ""] {
            XCTAssertFalse(DoubleSpacePeriodDecision.shouldReplace(
                documentContextBeforeInput: context,
                elapsedSincePreviousSpace: 0.2,
                isEnabled: true,
                isLatinQwertyTab: true,
                languageUsesLatinScript: true,
                fieldAllowsReplacement: true
            ), "Unexpected replacement for context \(context.debugDescription)")
        }
        XCTAssertFalse(DoubleSpacePeriodDecision.shouldReplace(
            documentContextBeforeInput: nil,
            elapsedSincePreviousSpace: 0.2,
            isEnabled: true,
            isLatinQwertyTab: true,
            languageUsesLatinScript: true,
            fieldAllowsReplacement: true
        ))
    }

    func testDoubleSpacePeriodRejectsExpiredTapAndURLField() {
        XCTAssertFalse(DoubleSpacePeriodDecision.shouldReplace(
            documentContextBeforeInput: "ciao ",
            elapsedSincePreviousSpace: 0.601,
            isEnabled: true,
            isLatinQwertyTab: true,
            languageUsesLatinScript: true,
            fieldAllowsReplacement: true
        ))
        XCTAssertFalse(DoubleSpacePeriodDecision.shouldReplace(
            documentContextBeforeInput: "example ",
            elapsedSincePreviousSpace: 0.2,
            isEnabled: true,
            isLatinQwertyTab: true,
            languageUsesLatinScript: true,
            fieldAllowsReplacement: false
        ))
    }

    func testLatinAutoCapitalizationSentenceBoundaries() {
        for context in ["", "Fine. ", "Davvero? ", "Sì!", "3.", "Riga\n", "A capo\n  ", "«Bene!» ", "Fine\u{2026} "] {
            XCTAssertTrue(shouldArmAutoCapitalization(context), "Expected sentence start for \(context.debugDescription)")
        }
    }

    func testLatinAutoCapitalizationRejectsNonBoundariesAndUnavailableContext() {
        for context in ["testo, ", "… ok ", "continua "] {
            XCTAssertFalse(shouldArmAutoCapitalization(context), "Unexpected sentence start for \(context.debugDescription)")
        }
        XCTAssertFalse(shouldArmAutoCapitalization(nil))
    }

    func testLatinAutoCapitalizationRejectsUnsafeOrIneligibleState() {
        XCTAssertFalse(shouldArmAutoCapitalization("", fieldAllows: false))
        XCTAssertFalse(shouldArmAutoCapitalization("", hostUsesSentences: false))
        XCTAssertFalse(shouldArmAutoCapitalization("", isLatinQwertyTab: false))
        XCTAssertFalse(shouldArmAutoCapitalization("", isComposing: true))
        XCTAssertFalse(shouldArmAutoCapitalization("", isShifted: true))
        XCTAssertFalse(shouldArmAutoCapitalization("", isCapsLocked: true))
    }

    private func shouldArmAutoCapitalization(
        _ context: String?,
        fieldAllows: Bool = true,
        hostUsesSentences: Bool = true,
        isLatinQwertyTab: Bool = true,
        isComposing: Bool = false,
        isShifted: Bool = false,
        isCapsLocked: Bool = false
    ) -> Bool {
        LatinAutoCapitalizationDecision.shouldArmShift(
            documentContextBeforeInput: context,
            isEnabled: true,
            isLatinQwertyTab: isLatinQwertyTab,
            languageUsesLatinScript: true,
            isShifted: isShifted,
            isCapsLocked: isCapsLocked,
            isComposing: isComposing,
            fieldAllowsAutoCapitalization: fieldAllows,
            hostUsesSentenceCapitalization: hostUsesSentences
        )
    }
}

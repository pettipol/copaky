//
//  CopakyBenchmarkTests.swift
//  Reproducible L0 writing benchmarks: keyboard geometry and decoder behaviour.
//

import UIKit
import XCTest

@MainActor
final class CopakyBenchmarkTests: CopakyCampaignTests {
    private enum BenchError: Error, CustomStringConvertible {
        case configuration(String)
        case missingElement(String)
        case unsupportedCharacter(Character)
        case input(String)

        var description: String {
            switch self {
            case .configuration(let message), .missingElement(let message), .input(let message): message
            case .unsupportedCharacter(let character): "unsupported character '\(character)'"
            }
        }
    }

    private struct GeometryKey {
        let label: String
        let frame: CGRect
        let role: String

        var json: [String: Any] {
            [
                "label": label,
                "x": Double(frame.minX),
                "y": Double(frame.minY),
                "w": Double(frame.width),
                "h": Double(frame.height),
                "role": role,
            ]
        }
    }

    private struct WordResult {
        let index: Int
        let expected: String
        let noisy: String
        let result: String
        let candidates: [String]
        let selectedCandidateIndex: Int?
        let taps: Int
        let milliseconds: Int

        var json: [String: Any] {
            [
                "index": index,
                "expected": expected,
                "noisy": noisy,
                "result": result,
                "candidates_before_space": candidates,
                "selected_candidate_index": selectedCandidateIndex.map { $0 as Any } ?? NSNull(),
                "taps": taps,
                "ms": milliseconds,
            ]
        }
    }

    private struct PhraseResult {
        let id: Int
        let block: String
        let op: String
        let expected: String
        let noisy: String
        let final: String
        let taps: Int
        let milliseconds: Int
        let error: String?
        let words: [WordResult]

        var json: [String: Any] {
            [
                "id": id,
                "block": block,
                "op": op,
                "expected": expected,
                "noisy": noisy,
                "final": final,
                "taps": taps,
                "ms": milliseconds,
                "error": error.map { $0 as Any } ?? NSNull(),
                "words": words.map(\.json),
            ]
        }
    }

    private struct LatinFixture {
        let id: Int
        let expected: String
        let noisy: String
        let block: String
        let op: String
        let parseError: String?
    }

    private struct JapaneseFixture {
        struct Segment {
            let reading: String
            let result: String
        }

        let id: Int
        let expected: String
        let reading: String
        let segments: [Segment]
        let parseError: String?
    }

    private let latinSpaceLabels = ["space", "Space", "spazio", "Spazio", "空白"]
    private let deleteLabels = ["delete", "Delete", "Cancella", "Elimina", "削除", "⌫"]
    private let returnLabels = ["return", "Return", "Invio", "A capo", "Newline", "改行"]

    private var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    private func environmentValue(_ name: String) -> String? {
        environment[name] ?? environment["TEST_RUNNER_\(name)"]
    }

    private var requestedKeyboard: String {
        let value = environmentValue("COPAKY_BENCH_KEYBOARD") ?? "copaky"
        return ["copaky", "apple"].contains(value) ? value : "copaky"
    }

    private var requestedLanguage: String {
        let value = environmentValue("COPAKY_BENCH_LANGUAGE") ?? "en"
        return ["en", "it", "ja"].contains(value) ? value : "en"
    }

    private var deviceName: String {
        environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name
    }

    private var osVersion: String {
        environment["SIMULATOR_RUNTIME_VERSION"] ?? UIDevice.current.systemVersion
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func keyboardFrame(for keyboard: String, timeout: TimeInterval = 6) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if keyboard == "copaky", let frame = keyboardInputViewFrame(of: safari), frame.width > 1, frame.height > 1 {
                return frame
            }
            let systemKeyboard = safari.keyboards.firstMatch
            if keyboard == "apple", systemKeyboard.exists, systemKeyboard.frame.width > 1, systemKeyboard.frame.height > 1 {
                return systemKeyboard.frame
            }
            wait(0.25)
        } while Date() < deadline
        return nil
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func emitJSON(_ object: Any, name: String) -> Data? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            XCTFail("Could not serialize benchmark JSON \(name)")
            return nil
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let outputDirectory = environmentValue("COPAKY_BENCH_OUT"), !outputDirectory.isEmpty {
            let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true).appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: outputURL, options: .atomic)
                print("COPAKY-BENCH-OUT|\(outputURL.path)")
            } catch {
                // The attachment remains the authoritative output when the simulator sandbox cannot
                // write the host path supplied by the orchestrator.
                print("COPAKY-BENCH-OUT-NOT-WRITABLE|\(outputURL.path)|\(error)")
            }
        }
        return data
    }

    private func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }.reduce("") { $0 + String($1) }
    }

    private func prepareKeyboard(fieldPlaceholder: String, keyboard: String, language: String) throws -> XCUIElement {
        let field = activatePreNavigatedField(fieldPlaceholder)
        if keyboard == "copaky" {
            switchToCopaky(in: safari)
            dismissCopakyNotice(in: safari)
            try switchCopakyLanguage(language)
        } else {
            let systemKeyboard = safari.keyboards.firstMatch
            guard systemKeyboard.waitForExistence(timeout: 8) else {
                throw BenchError.missingElement("Apple keyboard did not appear")
            }
        }
        guard keyboardFrame(for: keyboard) != nil else {
            throw BenchError.missingElement("Expected \(keyboard) keyboard frame did not appear")
        }
        return field
    }

    private func switchCopakyLanguage(_ language: String) throws {
        if language == "ja" {
            switchToJapaneseFlickTab(in: safari)
            let kana = safari.staticTexts.matching(NSPredicate(format: "label == %@", "か")).firstMatch
            guard kana.waitForExistence(timeout: 4) else {
                throw BenchError.missingElement("Copaky Japanese flick tab did not appear")
            }
            return
        }

        guard switchToLatinQwertyTab(in: safari) else {
            throw BenchError.missingElement("Copaky Latin QWERTY tab did not appear")
        }
        let desired = language == "it" ? "IT" : "A"
        for _ in 0..<5 {
            if let state = copakyLanguageSwitchState(), state.current == desired { return }
            guard let state = copakyLanguageSwitchState() else {
                throw BenchError.missingElement("Copaky language-switch identifier is missing")
            }
            tapCenter(of: state.element, in: safari)
            wait(0.8)
            dismissCopakyNotice(in: safari)
            if safari.staticTexts.matching(NSPredicate(format: "label == %@", "か")).firstMatch.exists {
                guard switchToLatinQwertyTab(in: safari) else {
                    throw BenchError.missingElement("Could not return from Japanese to Latin QWERTY")
                }
            }
        }
        throw BenchError.missingElement("Could not select Copaky language \(language)")
    }

    private func copakyLanguageSwitchState() -> (current: String, element: XCUIElement)? {
        let query = safari.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "keyboard-language-switch-")
        )
        for index in 0..<min(query.count, 12) {
            let element = query.element(boundBy: index)
            guard element.exists else { continue }
            let suffix = element.identifier.replacingOccurrences(of: "keyboard-language-switch-", with: "")
            guard let current = suffix.split(separator: "-").first.map(String.init) else { continue }
            return (current, element)
        }
        return nil
    }

    private func tapCenter(of element: XCUIElement, in app: XCUIApplication) {
        let frame = element.frame
        let appFrame = app.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: frame.midX - appFrame.minX, dy: frame.midY - appFrame.minY)
        ).tap()
    }

    // MARK: - test59 geometry

    func test59_keyboardGeometryBaseline() throws {
        let keyboard = requestedKeyboard
        let language = requestedLanguage
        let state = environmentValue("COPAKY_BENCH_STATE") ?? "default"

        do {
            _ = try prepareKeyboard(fieldPlaceholder: "plain-text", keyboard: keyboard, language: language)
        } catch {
            XCTFail(String(describing: error))
            return
        }
        wait(1.0)

        guard let inputFrame = keyboardFrame(for: keyboard) else {
            XCTFail("Keyboard frame disappeared before geometry capture")
            return
        }

        if keyboard == "apple" {
            let hasRequestedScript = language == "ja"
                ? systemKeyboardHasAnyLabel(["あ", "か", "さ"])
                : systemKeyboardHasAnyLabel(["a", "A", "q", "Q"])
            if !hasRequestedScript {
                let report = geometryJSON(
                    keyboard: keyboard,
                    language: language,
                    state: state,
                    inputFrame: inputFrame,
                    keys: [],
                    error: "requested system-keyboard language is not installed or active"
                )
                _ = emitJSON(report, name: "geometry-apple-\(language)-\(safeComponent(state)).json")
                attachScreenshot("59-apple-language-missing")
                throw XCTSkip("Apple \(language) keyboard must already exist and be active in the simulator")
            }
        }

        let keys = keyboard == "copaky"
            ? captureCopakyGeometry(in: inputFrame, language: language)
            : captureAppleGeometry(in: inputFrame)
        let invalidFrames = keys.filter { !frame($0.frame, isInside: inputFrame) }
        let error = invalidFrames.isEmpty
            ? nil
            : "\(invalidFrames.count) key frame(s) fall outside the keyboard frame"
        let report = geometryJSON(
            keyboard: keyboard,
            language: language,
            state: state,
            inputFrame: inputFrame,
            keys: keys,
            error: error
        )
        _ = emitJSON(report, name: "geometry-\(keyboard)-\(language)-\(safeComponent(state)).json")
        attachScreenshot("59-geometry-\(keyboard)-\(language)-\(safeComponent(state))")

        XCTAssertFalse(keys.isEmpty, "Geometry capture found no keys")
        XCTAssertTrue(invalidFrames.isEmpty, "Every captured key frame must be inside the keyboard frame")
    }

    private func geometryJSON(
        keyboard: String,
        language: String,
        state: String,
        inputFrame: CGRect,
        keys: [GeometryKey],
        error: String?
    ) -> [String: Any] {
        let letters = keys.filter { $0.role == "letter" }
        let letterWidths = letters.map { Double($0.frame.width) }
        let letterHeights = letters.map { Double($0.frame.height) }
        let rows = clusteredRows(keys)
        let horizontalGaps = rows.flatMap { row -> [Double] in
            let sorted = row.sorted { $0.frame.minX < $1.frame.minX }
            return zip(sorted, sorted.dropFirst()).map { max(0, Double($1.frame.minX - $0.frame.maxX)) }
        }
        let rowBounds = rows.compactMap { row -> CGRect? in
            row.map(\.frame).reduce(nil as CGRect?) { partial, frame in
                partial.map { $0.union(frame) } ?? frame
            }
        }.sorted { $0.minY < $1.minY }
        let verticalGaps = zip(rowBounds, rowBounds.dropFirst()).map { max(0, Double($1.minY - $0.maxY)) }
        let spaceWidth = keys.first(where: { $0.role == "space" }).map { Double($0.frame.width) } ?? 0

        var report: [String: Any] = [
            "device": deviceName,
            "os": osVersion,
            "keyboard": keyboard,
            "language": language,
            "state": state,
            "inputViewHeight": Double(inputFrame.height),
            "keys": keys.sorted {
                abs($0.frame.midY - $1.frame.midY) > 4 ? $0.frame.midY < $1.frame.midY : $0.frame.minX < $1.frame.minX
            }.map(\.json),
            "summary": [
                "letterWidthMedian": median(letterWidths),
                "letterWidthMin": letterWidths.min() ?? 0,
                "letterHeightMedian": median(letterHeights),
                "letterHeightMin": letterHeights.min() ?? 0,
                "spaceWidth": spaceWidth,
                "hGap": median(horizontalGaps),
                "vGap": median(verticalGaps),
                "rows": rows.count,
            ],
        ]
        if let error { report["error"] = error }
        return report
    }

    private func captureCopakyGeometry(in keyboardFrame: CGRect, language: String) -> [GeometryKey] {
        var keys: [GeometryKey] = []
        let letters = language == "ja"
            ? ["あ", "か", "さ", "た", "な", "は", "ま", "や", "ら", "わ"]
            : Array("qwertyuiopasdfghjklzxcvbnm").map(String.init)
        for label in letters {
            if let key = copakyTextKey(label: label, in: keyboardFrame) {
                appendUnique(GeometryKey(label: label.lowercased(), frame: key.frame, role: "letter"), to: &keys)
            } else if language != "ja" {
                let uppercase = label.uppercased()
                let text = uppercase == "A" ? visibleUppercaseLetter(uppercase) : visibleStaticText(labels: [uppercase], keyboard: "copaky")
                if let text, let key = smallestTouchContainer(around: text, in: keyboardFrame) {
                    appendUnique(GeometryKey(label: label.lowercased(), frame: key.frame, role: "letter"), to: &keys)
                }
            }
        }

        for digit in 0...9 {
            if let key = copakyIdentifierKey(identifier: "keyboard-number-row-\(digit)", in: keyboardFrame) {
                appendUnique(GeometryKey(label: "\(digit)", frame: key.frame, role: "digit"), to: &keys)
            }
        }
        let languageQuery = safari.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "keyboard-language-switch-")
        )
        for index in 0..<min(languageQuery.count, 12) {
            let descendant = languageQuery.element(boundBy: index)
            if descendant.exists,
               let key = smallestTouchContainer(around: descendant, in: keyboardFrame) {
                appendUnique(GeometryKey(label: descendant.label.isEmpty ? "language" : descendant.label, frame: key.frame, role: "language"), to: &keys)
            }
        }

        let imageKeys: [(identifier: String, label: String, role: String)] = [
            ("delete.left", "delete", "delete"),
            ("delete.backward", "delete", "delete"),
            ("arrow.turn.down.left", "return", "return"),
            ("shift", "shift", "shift"),
            ("shift.fill", "shift", "shift"),
            ("capslock.fill", "shift", "shift"),
            ("textformat.123", "123", "other"),
        ]
        for contract in imageKeys {
            if let key = copakyIdentifierKey(identifier: contract.identifier, in: keyboardFrame) {
                appendUnique(GeometryKey(label: contract.label, frame: key.frame, role: contract.role), to: &keys)
            }
        }

        for label in latinSpaceLabels {
            if let key = copakyTextKey(label: label, in: keyboardFrame) {
                appendUnique(GeometryKey(label: "space", frame: key.frame, role: "space"), to: &keys)
            }
        }
        for label in returnLabels {
            if let key = copakyTextKey(label: label, in: keyboardFrame) {
                appendUnique(GeometryKey(label: "return", frame: key.frame, role: "return"), to: &keys)
            }
        }
        for label in deleteLabels {
            if let key = copakyTextKey(label: label, in: keyboardFrame) {
                appendUnique(GeometryKey(label: "delete", frame: key.frame, role: "delete"), to: &keys)
            }
        }
        for label in [".", ",", "!", "?", "'", "\"", "小ﾞﾟ", "☆123", "ABC", "､｡?!"] {
            if let key = copakyTextKey(label: label, in: keyboardFrame) {
                appendUnique(GeometryKey(label: label, frame: key.frame, role: "other"), to: &keys)
            }
        }
        return keys
    }

    private func captureAppleGeometry(in keyboardFrame: CGRect) -> [GeometryKey] {
        var keys: [GeometryKey] = []
        let query = safari.keyboards.firstMatch.keys
        for index in 0..<query.count {
            let key = query.element(boundBy: index)
            guard key.exists, key.frame.width > 1, key.frame.height > 1 else { continue }
            appendUnique(
                GeometryKey(label: normalizedKeyLabel(key.label), frame: key.frame, role: role(for: key.label, identifier: key.identifier)),
                to: &keys
            )
        }
        return keys
    }

    private func copakyTextKey(label: String, in keyboardFrame: CGRect) -> XCUIElement? {
        let predicate = NSPredicate(format: "label == %@", label)
        let texts = safari.staticTexts.matching(predicate)
        for index in 0..<min(texts.count, 20) {
            let text = texts.element(boundBy: index)
            guard text.exists, frame(text.frame, isInside: keyboardFrame) else { continue }
            let containerQueries = [
                safari.otherElements.containing(predicate),
                safari.buttons.containing(predicate),
            ]
            if let container = smallestTouchContainer(from: containerQueries, around: text, in: keyboardFrame) {
                return container
            }
            return smallestTouchContainer(around: text, in: keyboardFrame)
        }
        return nil
    }

    private func copakyIdentifierKey(identifier: String, in keyboardFrame: CGRect) -> XCUIElement? {
        let descendant = safari.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", identifier)
        ).firstMatch
        guard descendant.waitForExistence(timeout: 0.4), frame(descendant.frame, isInside: keyboardFrame) else { return nil }
        return smallestTouchContainer(around: descendant, in: keyboardFrame)
    }

    private func smallestTouchContainer(
        from queries: [XCUIElementQuery]? = nil,
        around descendant: XCUIElement,
        in keyboardFrame: CGRect
    ) -> XCUIElement? {
        let queries = queries ?? [safari.otherElements, safari.buttons]
        var best: XCUIElement?
        var bestArea = CGFloat.greatestFiniteMagnitude
        let childFrame = descendant.frame
        for query in queries {
            for index in 0..<min(query.count, 180) {
                let candidate = query.element(boundBy: index)
                guard candidate.exists else { continue }
                let candidateFrame = candidate.frame
                let area = candidateFrame.width * candidateFrame.height
                guard candidateFrame.width > 1, candidateFrame.height > 1,
                      area > childFrame.width * childFrame.height * 1.05,
                      frame(candidateFrame, isInside: keyboardFrame),
                      candidateFrame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: childFrame.midX, y: childFrame.midY)),
                      area < bestArea else { continue }
                best = candidate
                bestArea = area
            }
        }
        return best
    }

    private func frame(_ candidate: CGRect, isInside container: CGRect) -> Bool {
        guard candidate.width > 0, candidate.height > 0 else { return false }
        let intersection = candidate.intersection(container.insetBy(dx: -1, dy: -1))
        return intersection.width >= candidate.width - 2 && intersection.height >= candidate.height - 2
    }

    private func appendUnique(_ key: GeometryKey, to keys: inout [GeometryKey]) {
        let duplicate = keys.contains {
            abs($0.frame.midX - key.frame.midX) < 1 && abs($0.frame.midY - key.frame.midY) < 1
                && abs($0.frame.width - key.frame.width) < 1 && abs($0.frame.height - key.frame.height) < 1
        }
        if !duplicate { keys.append(key) }
    }

    private func role(for label: String, identifier: String) -> String {
        let lowered = label.lowercased()
        if latinSpaceLabels.map({ $0.lowercased() }).contains(lowered) { return "space" }
        if deleteLabels.map({ $0.lowercased() }).contains(lowered) || identifier.contains("delete") { return "delete" }
        if returnLabels.map({ $0.lowercased() }).contains(lowered) || identifier.contains("return") { return "return" }
        if lowered.contains("shift") || lowered.contains("maiusc") || lowered.contains("大文字") { return "shift" }
        if lowered.contains("globe") || lowered.contains("tastiera successiva") || lowered.contains("next keyboard") || lowered.contains("次のキーボード") { return "language" }
        if label.count == 1, label.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) { return "digit" }
        if label.count == 1, label.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) { return "letter" }
        return "other"
    }

    private func normalizedKeyLabel(_ label: String) -> String {
        switch role(for: label, identifier: "") {
        case "space": "space"
        case "delete": "delete"
        case "return": "return"
        case "shift": "shift"
        case "letter": label.lowercased()
        default: label
        }
    }

    private func clusteredRows(_ keys: [GeometryKey]) -> [[GeometryKey]] {
        let layoutKeys = keys.filter { $0.role != "other" || $0.label != "写" }.sorted { $0.frame.midY < $1.frame.midY }
        var rows: [[GeometryKey]] = []
        for key in layoutKeys {
            if let index = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                return abs(first.frame.midY - key.frame.midY) <= max(4, min(first.frame.height, key.frame.height) * 0.35)
            }) {
                rows[index].append(key)
            } else {
                rows.append([key])
            }
        }
        return rows
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private func systemKeyboardHasAnyLabel(_ labels: [String]) -> Bool {
        let predicate = NSPredicate(format: "label IN %@", labels)
        return safari.keyboards.firstMatch.keys.matching(predicate).firstMatch.waitForExistence(timeout: 2)
    }

    // MARK: - test60 decoder

    func test60_benchDecoder() throws {
        let keyboard = requestedKeyboard
        let language = requestedLanguage
        let limit = max(1, Int(environmentValue("COPAKY_BENCH_LIMIT") ?? "100") ?? 100)
        let tsvPath = environmentValue("COPAKY_BENCH_TSV") ?? ""
        let tsvName = URL(fileURLWithPath: tsvPath).lastPathComponent
        let autocorrect: Bool? = keyboard == "copaky"
            ? parseBoolean(environmentValue("COPAKY_BENCH_AUTOCORRECT"))
            : nil
        let meta = benchmarkMeta(keyboard: keyboard, language: language, autocorrect: autocorrect, tsv: tsvName)

        guard !tsvPath.isEmpty, FileManager.default.isReadableFile(atPath: tsvPath) else {
            _ = emitJSON(["meta": meta, "phrases": []], name: "decoder-\(keyboard)-\(language)-missing-tsv.json")
            XCTFail("COPAKY_BENCH_TSV is missing or unreadable: \(tsvPath)")
            return
        }

        if keyboard == "apple", language == "ja" {
            var skippedMeta = meta
            skippedMeta["note"] = "Apple Japanese decoder benchmark is intentionally unsupported"
            _ = emitJSON(["meta": skippedMeta, "phrases": []], name: "decoder-apple-ja.json")
            throw XCTSkip("Apple + Japanese decoder benchmark is out of scope")
        }

        let field: XCUIElement
        do {
            field = try prepareKeyboard(fieldPlaceholder: "textarea-field", keyboard: keyboard, language: language)
        } catch {
            XCTFail(String(describing: error))
            return
        }
        if keyboard == "apple", !systemKeyboardHasAnyLabel(["a", "A", "q", "Q"]) {
            XCTFail("Expected Apple Latin keyboard did not appear")
            return
        }

        let contents: String
        do {
            contents = try String(contentsOfFile: tsvPath, encoding: .utf8)
        } catch {
            XCTFail("Could not read benchmark TSV: \(error)")
            return
        }

        let phrases: [PhraseResult]
        if language == "ja" {
            phrases = runJapaneseFixtures(parseJapaneseTSV(contents).prefix(limit), field: field, keyboard: keyboard)
        } else {
            phrases = runLatinFixtures(parseLatinTSV(contents).prefix(limit), field: field, keyboard: keyboard)
        }
        let report: [String: Any] = ["meta": meta, "phrases": phrases.map(\.json)]
        _ = emitJSON(report, name: "decoder-\(keyboard)-\(language).json")
        attachScreenshot("60-decoder-\(keyboard)-\(language)-complete")
    }

    private func benchmarkMeta(keyboard: String, language: String, autocorrect: Bool?, tsv: String) -> [String: Any] {
        let commit = environmentValue("COPAKY_BENCH_COMMIT").flatMap { $0.isEmpty ? nil : $0 }
        var meta: [String: Any] = [
            "device": deviceName,
            "os": osVersion,
            "keyboard": keyboard,
            "language": language,
            "autocorrect": autocorrect.map { $0 as Any } ?? NSNull(),
            "tsv": tsv,
            "commit": commit.map { $0 as Any } ?? NSNull(),
            "date": ISO8601DateFormatter().string(from: Date()),
        ]
        if keyboard == "apple" {
            meta["candidate_note"] = "predictive-bar candidates are empty when XCUI does not expose readable labels"
        }
        return meta
    }

    private func parseBoolean(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "1", "true", "yes", "on": true
        case "0", "false", "no", "off": false
        default: nil
        }
    }

    private func dataLines(_ contents: String) -> [(line: Int, columns: [String])] {
        var sawHeader = false
        var result: [(Int, [String])] = []
        for (offset, rawLine) in contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if !sawHeader {
                sawHeader = true
                continue
            }
            result.append((offset + 1, line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)))
        }
        return result
    }

    private func parseLatinTSV(_ contents: String) -> [LatinFixture] {
        dataLines(contents).enumerated().map { index, row in
            guard row.columns.count >= 4 else {
                return LatinFixture(id: index, expected: "", noisy: "", block: "", op: "", parseError: "malformed TSV line \(row.line)")
            }
            return LatinFixture(
                id: index,
                expected: row.columns[0],
                noisy: row.columns[1],
                block: row.columns[2],
                op: row.columns[3],
                parseError: nil
            )
        }
    }

    private func parseJapaneseTSV(_ contents: String) -> [JapaneseFixture] {
        dataLines(contents).enumerated().map { index, row in
            guard row.columns.count >= 5 else {
                return JapaneseFixture(id: index, expected: "", reading: "", segments: [], parseError: "malformed TSV line \(row.line)")
            }
            let id = Int(row.columns[0]) ?? index
            let segments = row.columns[3]
                .split(whereSeparator: { $0 == "|" || $0 == ";" || $0.isWhitespace })
                .compactMap { token -> JapaneseFixture.Segment? in
                    let pair = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard pair.count == 2 else { return nil }
                    return .init(
                        reading: String(pair[0]).trimmingCharacters(in: .whitespaces),
                        result: String(pair[1]).trimmingCharacters(in: .whitespaces)
                    )
                }
            let normalizedReading = row.columns[2].filter { !$0.isWhitespace }
            let segmentedReading = segments.map(\.reading).joined().filter { !$0.isWhitespace }
            let parseError: String?
            if segments.isEmpty {
                parseError = "no reading=result segments at TSV line \(row.line)"
            } else if normalizedReading != segmentedReading {
                parseError = "segment readings do not reconstruct reading_kana at TSV line \(row.line)"
            } else {
                parseError = nil
            }
            return JapaneseFixture(id: id, expected: row.columns[1], reading: row.columns[2], segments: segments, parseError: parseError)
        }
    }

    private func runLatinFixtures<C: Collection>(
        _ fixtures: C,
        field: XCUIElement,
        keyboard: String
    ) -> [PhraseResult] where C.Element == LatinFixture {
        fixtures.map { fixture in
            let started = Date()
            var taps = 0
            var words: [WordResult] = []
            var phraseError = fixture.parseError
            do {
                try clearBenchField(field, keyboard: keyboard)
                guard fixture.parseError == nil else { throw BenchError.input(fixture.parseError!) }
                let expectedWords = fixture.expected.split(whereSeparator: \.isWhitespace).map(String.init)
                let noisyWords = fixture.noisy.split(whereSeparator: \.isWhitespace).map(String.init)
                for (index, noisyWord) in noisyWords.enumerated() {
                    let wordStarted = Date()
                    var wordTaps = 0
                    for character in noisyWord {
                        try tapLatinCharacter(character, keyboard: keyboard)
                        taps += 1
                        wordTaps += 1
                    }
                    let candidates = candidateLabels(keyboard: keyboard)
                    let beforeSpace = currentFieldValue(field)
                    try tapSpace(keyboard: keyboard)
                    taps += 1
                    wordTaps += 1
                    let value = waitForValueChange(field, from: beforeSpace, timeout: 3)
                    let committedWords = value.split(whereSeparator: \.isWhitespace).map(String.init)
                    let result = index < committedWords.count ? committedWords[index] : (committedWords.last ?? "")
                    words.append(WordResult(
                        index: index,
                        expected: index < expectedWords.count ? expectedWords[index] : "",
                        noisy: noisyWord,
                        result: result,
                        candidates: candidates,
                        selectedCandidateIndex: nil,
                        taps: wordTaps,
                        milliseconds: elapsedMilliseconds(since: wordStarted)
                    ))
                }
            } catch {
                phraseError = phraseError ?? String(describing: error)
            }
            let final = currentFieldValue(field).trimmingCharacters(in: .whitespacesAndNewlines)
            if phraseError == nil, final != fixture.expected {
                phraseError = "final_mismatch"
            }
            return PhraseResult(
                id: fixture.id,
                block: fixture.block,
                op: fixture.op,
                expected: fixture.expected,
                noisy: fixture.noisy,
                final: final,
                taps: taps,
                milliseconds: elapsedMilliseconds(since: started),
                error: phraseError,
                words: words
            )
        }
    }

    private func runJapaneseFixtures<C: Collection>(
        _ fixtures: C,
        field: XCUIElement,
        keyboard: String
    ) -> [PhraseResult] where C.Element == JapaneseFixture {
        fixtures.map { fixture in
            let started = Date()
            var taps = 0
            var phraseError = fixture.parseError
            var words: [WordResult] = []
            do {
                try clearBenchField(field, keyboard: keyboard)
                guard fixture.parseError == nil else { throw BenchError.input(fixture.parseError!) }
                for (index, segment) in fixture.segments.enumerated() {
                    let segmentStarted = Date()
                    let segmentTaps = try tapFlickString(segment.reading)
                    taps += segmentTaps
                    let candidates = waitForCandidates(keyboard: keyboard, timeout: 3)
                    let selected = candidates.firstIndex(of: segment.result) ?? -1
                    if selected >= 0 {
                        guard let candidate = candidateElement(label: segment.result, keyboard: keyboard) else {
                            throw BenchError.missingElement("candidate '\(segment.result)' disappeared")
                        }
                        candidate.tap()
                        taps += 1
                        wait(0.5)
                    }
                    let result = selected >= 0 ? segment.result : ""
                    words.append(WordResult(
                        index: index,
                        expected: segment.result,
                        noisy: segment.reading,
                        result: result,
                        candidates: candidates,
                        selectedCandidateIndex: selected,
                        taps: segmentTaps + (selected >= 0 ? 1 : 0),
                        milliseconds: elapsedMilliseconds(since: segmentStarted)
                    ))
                    if selected < 0, phraseError == nil {
                        phraseError = "expected candidate missing at segment \(index)"
                    }
                }
            } catch {
                phraseError = phraseError ?? String(describing: error)
            }
            let final = currentFieldValue(field)
            if phraseError == nil, final != fixture.expected { phraseError = "final_mismatch" }
            return PhraseResult(
                id: fixture.id,
                block: "JA",
                op: "convert",
                expected: fixture.expected,
                noisy: fixture.reading,
                final: final,
                taps: taps,
                milliseconds: elapsedMilliseconds(since: started),
                error: phraseError,
                words: words
            )
        }
    }

    private func elapsedMilliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1_000)
    }

    private func currentFieldValue(_ field: XCUIElement) -> String {
        let value = field.value as? String ?? ""
        return value == "textarea-field" || value == "plain-text" ? "" : value
    }

    private func waitForValueChange(_ field: XCUIElement, from oldValue: String, timeout: TimeInterval) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let value = currentFieldValue(field)
            if value != oldValue, value.last?.isWhitespace == true { return value }
            wait(0.2)
        } while Date() < deadline
        return currentFieldValue(field)
    }

    private func clearBenchField(_ field: XCUIElement, keyboard: String) throws {
        field.tap()
        var value = currentFieldValue(field)
        guard !value.isEmpty else { return }

        field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        let selectAllLabels = ["Seleziona tutto", "Select All", "すべてを選択"]
        let selectAll = safari.menuItems.matching(NSPredicate(format: "label IN %@", selectAllLabels)).firstMatch
        let selectAllButton = safari.buttons.matching(NSPredicate(format: "label IN %@", selectAllLabels)).firstMatch
        if selectAll.waitForExistence(timeout: 1), selectAll.isHittable {
            selectAll.tap()
        } else if selectAllButton.exists, selectAllButton.isHittable {
            selectAllButton.tap()
        }
        if let delete = deleteKey(keyboard: keyboard) {
            delete.tap()
            wait(0.25)
        }
        value = currentFieldValue(field)
        if !value.isEmpty {
            guard let delete = deleteKey(keyboard: keyboard) else {
                throw BenchError.missingElement("delete key is missing while clearing the textarea")
            }
            for _ in value { delete.tap() }
            wait(0.4)
        }
        guard currentFieldValue(field).isEmpty else {
            throw BenchError.input("textarea could not be cleared")
        }
    }

    private func deleteKey(keyboard: String) -> XCUIElement? {
        if keyboard == "apple" {
            let query = safari.keyboards.firstMatch.keys.matching(NSPredicate(format: "label IN %@", deleteLabels))
            return query.firstMatch.waitForExistence(timeout: 1) ? query.firstMatch : nil
        }
        for identifier in ["delete.left", "delete.backward"] {
            let key = safari.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
            if key.waitForExistence(timeout: 0.4) { return key }
        }
        let key = safari.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", deleteLabels)).firstMatch
        return key.waitForExistence(timeout: 1) ? key : nil
    }

    private func tapSpace(keyboard: String) throws {
        let key: XCUIElement
        if keyboard == "apple" {
            key = safari.keyboards.firstMatch.keys.matching(NSPredicate(format: "label IN %@", latinSpaceLabels)).firstMatch
        } else {
            key = safari.staticTexts.matching(NSPredicate(format: "label IN %@", latinSpaceLabels)).firstMatch
        }
        guard key.waitForExistence(timeout: 2) else { throw BenchError.missingElement("space key is missing") }
        key.tap()
    }

    private func tapLatinCharacter(_ character: Character, keyboard: String) throws {
        if let accent = accentDefinition(for: character) {
            if character.isUppercase { try tapShift(keyboard: keyboard) }
            if keyboard == "apple" {
                try tapAppleAccent(character, base: accent.base)
            } else {
                try tapCopakyAccent(character, definition: accent)
            }
            return
        }
        if [".", ",", "!", "?", "'", "\""].contains(String(character)) {
            if keyboard == "apple" {
                try tapApplePunctuation(character)
            } else {
                try tapCopakyPunctuation(character)
            }
            return
        }

        let raw = String(character)
        let key: XCUIElement?
        if keyboard == "apple" {
            if character.isUppercase { try tapShift(keyboard: keyboard) }
            let query = safari.keyboards.firstMatch.keys.matching(NSPredicate(format: "label == %@", raw))
            key = query.firstMatch.waitForExistence(timeout: 2) ? query.firstMatch : nil
        } else if character.isUppercase {
            try tapShift(keyboard: keyboard)
            key = visibleUppercaseLetter(raw)
        } else {
            // Exact lowercase lookup avoids the A-language-key ambiguity called out in the XCUI playbook.
            key = visibleStaticText(labels: [raw], keyboard: keyboard)
        }
        guard let key else { throw BenchError.unsupportedCharacter(character) }
        key.tap()
    }

    private func tapShift(keyboard: String) throws {
        let shift: XCUIElement
        if keyboard == "apple" {
            shift = safari.keyboards.firstMatch.keys.matching(
                NSPredicate(format: "label CONTAINS[c] 'shift' OR label CONTAINS[c] 'maiusc' OR label CONTAINS '大文字'")
            ).firstMatch
        } else {
            shift = safari.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@", "shift")
            ).firstMatch
        }
        guard shift.waitForExistence(timeout: 2) else { throw BenchError.missingElement("shift key is missing") }
        shift.tap()
        wait(0.2)
    }

    private func visibleUppercaseLetter(_ label: String) -> XCUIElement? {
        guard let frame = keyboardFrame(for: "copaky") else { return nil }
        let candidates = safari.staticTexts.matching(NSPredicate(format: "label == %@", label))
        let referenceLabel = label == "S" ? "D" : "S"
        let reference = safari.staticTexts.matching(NSPredicate(format: "label == %@", referenceLabel)).firstMatch
        guard reference.waitForExistence(timeout: 2) else { return nil }
        var best: XCUIElement?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in 0..<min(candidates.count, 20) {
            let candidate = candidates.element(boundBy: index)
            guard candidate.exists, self.frame(candidate.frame, isInside: frame) else { continue }
            let distance = abs(candidate.frame.midY - reference.frame.midY)
            if distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }

    private typealias AccentDefinition = (base: String, variations: [String], direction: String)

    private func accentDefinition(for character: Character) -> AccentDefinition? {
        let definitions: [String: AccentDefinition] = [
            "a": ("a", ["à", "á", "â", "ä", "ã"], "right"),
            "e": ("e", ["è", "é", "ê", "ë"], "right"),
            "i": ("i", ["ì", "í", "î", "ï"], "left"),
            "o": ("o", ["ò", "ó", "ô", "ö", "õ"], "left"),
            "u": ("u", ["ù", "ú", "û", "ü"], "left"),
            "n": ("n", ["ñ"], "left"),
            "c": ("c", ["ç"], "right"),
        ]
        let target = String(character).lowercased()
        return definitions.first(where: { $0.value.variations.contains(target) })?.value
    }

    private func tapCopakyAccent(_ character: Character, definition: AccentDefinition) throws {
        guard let source = visibleStaticText(labels: [definition.base], keyboard: "copaky"),
              let frame = keyboardFrame(for: "copaky") else {
            throw BenchError.missingElement("base key '\(definition.base)' is missing")
        }
        let target = String(character).lowercased()
        guard let index = definition.variations.firstIndex(of: target) else {
            throw BenchError.unsupportedCharacter(character)
        }
        let touchFrame = smallestTouchContainer(around: source, in: frame)?.frame ?? source.frame
        let width = max(touchFrame.width, 28)
        let dx: CGFloat = definition.direction == "right"
            ? width * (CGFloat(index) + 0.35)
            : -width * (CGFloat(definition.variations.count - index) - 0.5)
        let appFrame = safari.frame
        let start = safari.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: touchFrame.midX - appFrame.minX, dy: touchFrame.midY - appFrame.minY)
        )
        start.press(forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: dx, dy: 0)))
        wait(0.25)
    }

    private func tapAppleAccent(_ character: Character, base: String) throws {
        let keyboard = safari.keyboards.firstMatch
        let baseKey = keyboard.keys.matching(NSPredicate(format: "label IN %@", [base, base.uppercased()])).firstMatch
        guard baseKey.waitForExistence(timeout: 2) else { throw BenchError.missingElement("Apple base key '\(base)' is missing") }
        baseKey.press(forDuration: 0.8)
        let target = String(character)
        let variant = keyboard.keys.matching(NSPredicate(format: "label IN %@", [target, target.uppercased()])).firstMatch
        let fallback = safari.staticTexts.matching(NSPredicate(format: "label IN %@", [target, target.uppercased()])).firstMatch
        if variant.waitForExistence(timeout: 2), variant.isHittable {
            variant.tap()
        } else if fallback.exists, fallback.isHittable {
            fallback.tap()
        } else {
            throw BenchError.missingElement("Apple accent variant '\(character)' is missing")
        }
    }

    private func tapCopakyPunctuation(_ character: Character) throws {
        let target = String(character)
        if target == ".", let dot = visibleStaticText(labels: ["."], keyboard: "copaky") {
            dot.tap()
            return
        }
        let variations = [".", ",", "!", "?", "'", "\""]
        guard let index = variations.firstIndex(of: target),
              let source = visibleStaticText(labels: ["."], keyboard: "copaky"),
              let keyboardFrame = keyboardFrame(for: "copaky") else {
            throw BenchError.unsupportedCharacter(character)
        }
        let touchFrame = smallestTouchContainer(around: source, in: keyboardFrame)?.frame ?? source.frame
        let width = max(touchFrame.width, 28)
        let dx = -width * (CGFloat(variations.count - index) - 0.5)
        let appFrame = safari.frame
        let start = safari.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: touchFrame.midX - appFrame.minX, dy: touchFrame.midY - appFrame.minY)
        )
        start.press(forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: dx, dy: 0)))
        wait(0.25)
    }

    private func tapApplePunctuation(_ character: Character) throws {
        let target = String(character)
        let keyboard = safari.keyboards.firstMatch
        var key = keyboard.keys.matching(NSPredicate(format: "label == %@", target)).firstMatch
        if !key.waitForExistence(timeout: 0.5) {
            let numbersLabels = ["123", "Numeri", "Numbers", "数字"]
            let numbers = keyboard.keys.matching(NSPredicate(format: "label IN %@", numbersLabels)).firstMatch
            guard numbers.waitForExistence(timeout: 1) else { throw BenchError.unsupportedCharacter(character) }
            numbers.tap()
            wait(0.3)
            key = keyboard.keys.matching(NSPredicate(format: "label == %@", target)).firstMatch
        }
        guard key.waitForExistence(timeout: 1) else { throw BenchError.unsupportedCharacter(character) }
        key.tap()
        let letters = keyboard.keys.matching(NSPredicate(format: "label IN %@", ["ABC", "Lettere", "Letters", "英字"])).firstMatch
        if letters.waitForExistence(timeout: 0.5) { letters.tap(); wait(0.2) }
    }

    private func visibleStaticText(labels: [String], keyboard: String) -> XCUIElement? {
        guard let frame = keyboardFrame(for: keyboard) else { return nil }
        let query = safari.staticTexts.matching(NSPredicate(format: "label IN %@", labels))
        for index in 0..<min(query.count, 30) {
            let element = query.element(boundBy: index)
            if element.exists, self.frame(element.frame, isInside: frame) { return element }
        }
        return nil
    }

    private func candidateLabels(keyboard: String) -> [String] {
        guard let frame = keyboardFrame(for: keyboard) else { return [] }
        let keyTop: CGFloat
        if keyboard == "apple" {
            let keys = safari.keyboards.firstMatch.keys
            var top = CGFloat.greatestFiniteMagnitude
            for index in 0..<keys.count {
                let key = keys.element(boundBy: index)
                if key.exists, key.frame.height > 1 { top = min(top, key.frame.minY) }
            }
            keyTop = top
        } else {
            let anchors = safari.staticTexts.matching(NSPredicate(format: "label IN %@", ["q", "Q", "あ", "か", "さ"]))
            var top = CGFloat.greatestFiniteMagnitude
            for index in 0..<min(anchors.count, 20) {
                let anchor = anchors.element(boundBy: index)
                if anchor.exists, self.frame(anchor.frame, isInside: frame) { top = min(top, anchor.frame.minY) }
            }
            keyTop = top
        }
        guard keyTop.isFinite else { return [] }

        var candidates: [(String, CGFloat)] = []
        let texts = safari.staticTexts
        for index in 0..<min(texts.count, 240) {
            let element = texts.element(boundBy: index)
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard element.exists, !label.isEmpty,
                  element.frame.midY >= frame.minY - 1,
                  element.frame.maxY < keyTop - 1,
                  element.frame.midX >= frame.minX,
                  element.frame.midX <= frame.maxX else { continue }
            candidates.append((label, element.frame.minX))
        }
        if keyboard == "apple" {
            let others = safari.keyboards.firstMatch.otherElements
            for index in 0..<min(others.count, 80) {
                let element = others.element(boundBy: index)
                let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard element.exists, !label.isEmpty,
                      element.frame.midY >= frame.minY - 1,
                      element.frame.maxY < keyTop - 1 else { continue }
                candidates.append((label, element.frame.minX))
            }
        }
        var seen = Set<String>()
        return candidates.sorted { $0.1 < $1.1 }.compactMap { label, _ in
            guard !["写", "取り消す", "お知らせ", "逆順"].contains(label) else { return nil }
            return seen.insert(label).inserted ? label : nil
        }
    }

    private func waitForCandidates(keyboard: String, timeout: TimeInterval) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let labels = candidateLabels(keyboard: keyboard)
            if !labels.isEmpty { return labels }
            wait(0.2)
        } while Date() < deadline
        return candidateLabels(keyboard: keyboard)
    }

    private func candidateElement(label: String, keyboard: String) -> XCUIElement? {
        guard let frame = keyboardFrame(for: keyboard) else { return nil }
        let texts = safari.staticTexts.matching(NSPredicate(format: "label == %@", label))
        for index in 0..<min(texts.count, 20) {
            let element = texts.element(boundBy: index)
            guard element.exists, element.frame.midY >= frame.minY - 1, element.frame.midY <= frame.midY else { continue }
            return element
        }
        return nil
    }

    // MARK: Japanese flick input

    private struct FlickStroke {
        let base: String
        let dx: CGFloat
        let dy: CGFloat
        let modifiers: Int
    }

    private func tapFlickString(_ value: String) throws -> Int {
        var taps = 0
        for character in value {
            if character.isWhitespace {
                let space = safari.staticTexts.matching(NSPredicate(format: "label == %@", "空白")).firstMatch
                guard space.waitForExistence(timeout: 2) else { throw BenchError.missingElement("Japanese space key is missing") }
                space.tap()
                taps += 1
                continue
            }
            let stroke = try flickStroke(for: character)
            guard let key = visibleStaticText(labels: [stroke.base], keyboard: "copaky") else {
                throw BenchError.missingElement("flick base key '\(stroke.base)' is missing")
            }
            if stroke.dx == 0, stroke.dy == 0 {
                key.tap()
            } else {
                let frame = key.frame
                let appFrame = safari.frame
                let start = safari.coordinate(withNormalizedOffset: .zero).withOffset(
                    CGVector(dx: frame.midX - appFrame.minX, dy: frame.midY - appFrame.minY)
                )
                start.press(
                    forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: stroke.dx * 52, dy: stroke.dy * 52))
                )
            }
            taps += 1
            if stroke.modifiers > 0 {
                let modifier = safari.staticTexts.matching(NSPredicate(format: "label == %@", "小ﾞﾟ")).firstMatch
                guard modifier.waitForExistence(timeout: 2) else { throw BenchError.missingElement("Japanese modifier key is missing") }
                for _ in 0..<stroke.modifiers {
                    modifier.tap()
                    taps += 1
                }
            }
        }
        return taps
    }

    private func flickStroke(for character: Character) throws -> FlickStroke {
        let groups: [(String, [Character])] = [
            ("あ", Array("あいうえお")), ("か", Array("かきくけこ")), ("さ", Array("さしすせそ")),
            ("た", Array("たちつてと")), ("な", Array("なにぬねの")), ("は", Array("はひふへほ")),
            ("ま", Array("まみむめも")), ("ら", Array("らりるれろ")),
        ]
        let vectors: [(CGFloat, CGFloat)] = [(0, 0), (-1, 0), (0, -1), (1, 0), (0, 1)]
        for (base, values) in groups {
            if let index = values.firstIndex(of: character) {
                return FlickStroke(base: base, dx: vectors[index].0, dy: vectors[index].1, modifiers: 0)
            }
        }
        let irregular: [Character: FlickStroke] = [
            "や": .init(base: "や", dx: 0, dy: 0, modifiers: 0),
            "ゆ": .init(base: "や", dx: 0, dy: -1, modifiers: 0),
            "よ": .init(base: "や", dx: 0, dy: 1, modifiers: 0),
            "わ": .init(base: "わ", dx: 0, dy: 0, modifiers: 0),
            "を": .init(base: "わ", dx: -1, dy: 0, modifiers: 0),
            "ん": .init(base: "わ", dx: 0, dy: -1, modifiers: 0),
            "ー": .init(base: "わ", dx: 1, dy: 0, modifiers: 0),
        ]
        if let stroke = irregular[character] { return stroke }

        let transformations: [Character: (plain: Character, modifiers: Int)] = [
            "ぁ": ("あ", 1), "ぃ": ("い", 1), "ぅ": ("う", 1), "ぇ": ("え", 1), "ぉ": ("お", 1),
            "ゃ": ("や", 1), "ゅ": ("ゆ", 1), "ょ": ("よ", 1), "ゎ": ("わ", 1), "っ": ("つ", 1), "ゔ": ("う", 2),
            "が": ("か", 1), "ぎ": ("き", 1), "ぐ": ("く", 1), "げ": ("け", 1), "ご": ("こ", 1),
            "ざ": ("さ", 1), "じ": ("し", 1), "ず": ("す", 1), "ぜ": ("せ", 1), "ぞ": ("そ", 1),
            "だ": ("た", 1), "ぢ": ("ち", 1), "づ": ("つ", 2), "で": ("て", 1), "ど": ("と", 1),
            "ば": ("は", 1), "び": ("ひ", 1), "ぶ": ("ふ", 1), "べ": ("へ", 1), "ぼ": ("ほ", 1),
            "ぱ": ("は", 2), "ぴ": ("ひ", 2), "ぷ": ("ふ", 2), "ぺ": ("へ", 2), "ぽ": ("ほ", 2),
        ]
        if let transformed = transformations[character] {
            var stroke = try flickStroke(for: transformed.plain)
            stroke = FlickStroke(base: stroke.base, dx: stroke.dx, dy: stroke.dy, modifiers: transformed.modifiers)
            return stroke
        }
        throw BenchError.unsupportedCharacter(character)
    }
}

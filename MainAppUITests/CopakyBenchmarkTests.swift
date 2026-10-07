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
                "candidate_observation": candidates.isEmpty ? "unavailable" : "observed",
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
        let expectedRaw: String
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
                "expected_raw": expectedRaw,
                "noisy": noisy,
                "final": final,
                "final_trimmed_diagnostic": final.trimmingCharacters(in: .whitespacesAndNewlines),
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
        environmentValue("COPAKY_BENCH_KEYBOARD") ?? "copaky"
    }

    private var requestedLanguage: String {
        environmentValue("COPAKY_BENCH_LANGUAGE") ?? "en"
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
        guard ["en", "it", "ja"].contains(language) else {
            throw BenchError.configuration("Invalid COPAKY_BENCH_LANGUAGE: \(language)")
        }
        // Copaky: a visible Keyboard element does not establish its provider or locale.
        // Copaky: Keyboard要素だけでは提供元・言語を証明できないため比較を拒否する。
        guard keyboard == "copaky" else {
            throw BenchError.configuration("UNSUPPORTED: Apple provider/language selection is not proved by this harness")
        }
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
            _ = emitJSON(["keyboard": keyboard, "language": language, "state": state, "keys": [], "error": String(describing: error)], name: "geometry-\(keyboard)-\(language)-setup-failed.json")
            attachScreenshot("59-setup-failed")
            XCTFail(String(describing: error))
            return
        }
        wait(1.0)
        attachScreenshot("59-before-geometry-query")
        let geometryTree = XCTAttachment(string: safari.debugDescription)
        geometryTree.name = "59-geometry-tree"
        geometryTree.lifetime = .keepAlways
        add(geometryTree)

        guard let inputFrame = keyboardFrame(for: keyboard) else {
            XCTFail("Keyboard frame disappeared before geometry capture")
            return
        }
        // Copaky: retained AX keyboard trees can sit below the screen after a host round trip.
        // Copaky: ホスト復帰後の画面外AXツリーを実際に表示されたキーボードとして測定しない。
        // Copaky: the UI-test runner's UIScreen can be 320×480 while target Safari is 440×956.
        // Its bounds are diagnostic only; the target's actual window is the qualified viewport.
        // Copaky: ランナーのUIScreenではなく、実際のSafariウィンドウを表示領域として使う。
        let screenFrame = UIScreen.main.bounds
        let hostFrame = safari.frame
        let anchors = safari.staticTexts.matching(NSPredicate(format: "label IN %@", language == "ja" ? ["あ", "か", "さ"] : ["q", "Q"]))
        let hasVisibleLetter = anchors.allElementsBoundByIndex.prefix(20).contains {
            guard $0.exists else { return false }
            let measured = $0.frame
            guard frame(measured, isInside: inputFrame), hostFrame.insetBy(dx: -1, dy: -1).contains(measured) else { return false }
            return $0.isHittable
        }
        guard hostFrame.insetBy(dx: -1, dy: -1).contains(inputFrame), hasVisibleLetter else {
            func bounds(_ rect: CGRect) -> [String: Double] {
                ["x": Double(rect.minX), "y": Double(rect.minY), "w": Double(rect.width), "h": Double(rect.height)]
            }
            let anchorDiagnostics: [[String: Any]] = anchors.allElementsBoundByIndex.prefix(20).enumerated().map { index, anchor in
                guard anchor.exists else { return ["index": index, "exists": false] }
                let anchorFrame = anchor.frame
                let validFrame = frame(anchorFrame, isInside: inputFrame) && hostFrame.insetBy(dx: -1, dy: -1).contains(anchorFrame)
                return ["index": index, "exists": true, "label": anchor.label, "frame": bounds(anchorFrame), "isHittable": validFrame ? anchor.isHittable as Any : NSNull(),
                        "inside_inputView": frame(anchorFrame, isInside: inputFrame),
                        "inside_safari": hostFrame.insetBy(dx: -1, dy: -1).contains(anchorFrame),
                        "inside_screen": screenFrame.insetBy(dx: -1, dy: -1).contains(anchorFrame)]
            }
            var report = geometryJSON(keyboard: keyboard, language: language, state: state, inputFrame: inputFrame, keys: [], error: "HOLD: inputView or Copaky letter is not visible and hittable on screen")
            report["visibility_diagnostics"] = ["inputFrame": bounds(inputFrame), "safariFrame": bounds(hostFrame), "screenFrame": bounds(screenFrame),
                                                "viewport_source": "Safari target window; runner UIScreen is diagnostic only",
                                                "input_inside_safari": hostFrame.insetBy(dx: -1, dy: -1).contains(inputFrame),
                                                "input_inside_screen": screenFrame.insetBy(dx: -1, dy: -1).contains(inputFrame),
                                                "has_visible_letter_at_gate": hasVisibleLetter, "anchors": anchorDiagnostics]
            _ = emitJSON(report, name: "geometry-\(keyboard)-\(language)-offscreen.json")
            attachScreenshot("59-offscreen-keyboard")
            XCTFail("HOLD: geometry requires an on-screen inputView and a hittable Copaky letter")
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
        let invalidFrames = keys.filter {
            !frame($0.frame, isInside: inputFrame)
                || !hostFrame.insetBy(dx: -1, dy: -1).contains($0.frame)
        }
        let requiredLetters = language == "ja" ? 10 : 26
        let letters = keys.filter { $0.role == "letter" }
        let validLetters = Set(letters.filter { isKeyCell($0.frame, in: inputFrame, letter: true) }.map(\.label))
        let missingControlRoles = ["space", "delete", "return"].filter { role in !keys.contains { $0.role == role } }
        let error: String? = !invalidFrames.isEmpty
            ? "\(invalidFrames.count) key frame(s) fall outside the keyboard frame"
            : validLetters.count != requiredLetters
                ? "HOLD: expected \(requiredLetters) unique key-sized letter cells; got \(validLetters.count)"
                : !missingControlRoles.isEmpty
                    ? "HOLD: missing measured control cells: \(missingControlRoles.joined(separator: ", "))"
                    : nil
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

        XCTAssertEqual(validLetters.count, requiredLetters, "Geometry requires all distinct letter cells; containers and glyph bounds are not key geometry")
        XCTAssertTrue(invalidFrames.isEmpty, "Every captured key frame must be inside the keyboard frame")
        XCTAssertTrue(missingControlRoles.isEmpty, "HOLD: geometry also requires measured space, delete and return cells; missing \(missingControlRoles)")
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
                if let key = copakyTextKey(label: uppercase, in: keyboardFrame) {
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
            // Copaky: use a proven hittable cell leaf directly; glyphs still require a container.
            if isKeyCell(text.frame, in: keyboardFrame, letter: label.count == 1 && label.first?.isLetter == true),
               safari.frame.insetBy(dx: -1, dy: -1).contains(text.frame), text.isHittable {
                return text
            }
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
        if let container = smallestTouchContainer(around: descendant, in: keyboardFrame) { return container }
        // Copaky: an AX Image is measurable only if it exposes a real, hittable key cell.
        // Copaky: 実キー寸法とヒット判定のあるImageだけを認め、字形の寸法は採用しない。
        if descendant.elementType == .image, isKeyCell(descendant.frame, in: keyboardFrame, letter: false),
           safari.frame.insetBy(dx: -1, dy: -1).contains(descendant.frame), descendant.isHittable { return descendant }
        return nil
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
                guard isKeyCell(candidateFrame, in: keyboardFrame, letter: descendant.label.count == 1 && descendant.label.first?.isLetter == true),
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

    private func isKeyCell(_ candidate: CGRect, in keyboardFrame: CGRect, letter: Bool) -> Bool {
        // Copaky: reject glyphs and whole-row/inputView ancestors (e.g. 440×250).
        // Copaky: 字形の境界と行全体・inputViewの祖先をキー寸法として認めない。
        candidate.width >= 20 && candidate.height >= 30
            && candidate.width <= keyboardFrame.width * (letter ? 0.34 : 0.8)
            && candidate.height <= keyboardFrame.height * 0.34
            && frame(candidate, isInside: keyboardFrame)
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
            XCTFail("UNSUPPORTED: Apple + Japanese decoder benchmark is out of scope")
            return
        }

        let field: XCUIElement
        do {
            field = try prepareKeyboard(fieldPlaceholder: "textarea-field", keyboard: keyboard, language: language)
        } catch {
            _ = emitJSON(["meta": meta, "phrases": [], "error": String(describing: error)], name: "decoder-\(keyboard)-\(language)-setup-failed.json")
            attachScreenshot("60-setup-failed")
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

        var completed: [PhraseResult] = []
        func recordProgress(_ phrase: PhraseResult) {
            completed.append(phrase)
            // Copaky: completed observations survive a later XCUI failure, but cannot qualify a run.
            _ = emitJSON(["meta": meta, "phrases": completed.map(\.json), "status": "PARTIAL"],
                         name: "decoder-progress-\(keyboard)-\(language)-\(completed.count).json")
        }
        let phrases: [PhraseResult]
        if language == "ja" {
            phrases = runJapaneseFixtures(parseJapaneseTSV(contents).prefix(limit), field: field, keyboard: keyboard, onFixture: recordProgress)
        } else {
            phrases = runLatinFixtures(parseLatinTSV(contents).prefix(limit), field: field, keyboard: keyboard, onFixture: recordProgress)
        }
        let report: [String: Any] = ["meta": meta, "phrases": phrases.map(\.json)]
        _ = emitJSON(report, name: "decoder-\(keyboard)-\(language).json")
        attachScreenshot("60-decoder-\(keyboard)-\(language)-complete")
        let completedTree = XCTAttachment(string: safari.debugDescription)
        completedTree.name = "60-decoder-\(keyboard)-\(language)-tree-complete"
        completedTree.lifetime = .keepAlways
        add(completedTree)
        // Copaky: attach every observation before reporting a failing phrase.
        XCTAssertFalse(phrases.isEmpty, "Benchmark TSV contains no data fixtures")
        let failures = phrases.filter { $0.error != nil }
        XCTAssertTrue(failures.isEmpty, "Decoder failed: \(failures.map { "\($0.id): \($0.error ?? "unknown")" }.joined(separator: "; "))")
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
            "keystroke_count_status": "NOT_QUALIFIED",
            "taps_semantics": "logical_input_actions_excluding_navigation",
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

    // Copaky: independent IT/EN/JA runs, literal keys only; settings are read, never changed.
    // Copaky: 伊英日を別実行し、実キーだけを使う。設定は読み取りのみ。
    func test62_realTypingScenarios() throws {
        let language = requestedLanguage
        var checkpoints: [[String: Any]] = []
        var error: String?
        var taps = 0
        let started = Date()
        do {
            guard requestedKeyboard == "copaky" else { throw BenchError.configuration("test62 requires Copaky") }
            guard ["en", "it", "ja"].contains(language) else { throw BenchError.configuration("Invalid COPAKY_BENCH_LANGUAGE: \(language)") }
            // test61: stop Safari BEFORE MainApp setup to avoid its background keyboard watchdog.
            safari.terminate()
            mainApp.terminate()
            mainApp.launch()
            let close = mainApp.buttons.matching(NSPredicate(format: "label IN %@", ["閉じる", "Close", "Chiudi"])).firstMatch
            if close.waitForExistence(timeout: 3), close.isHittable { close.tap() }
            let settings = mainApp.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["設定", "Settings", "Impostazioni"])).firstMatch
            guard settings.waitForExistence(timeout: 3), settings.isHittable else { throw BenchError.missingElement("MainApp Settings tab missing") }
            settings.tap()
            wait(0.5)
            var contracts: [(String, [String])] = [("live_conversion", ["ライブ変換", "Live Conversion", "Conversione live"])]
            if language != "ja" {
                contracts += [
                    ("enable_latin_autocorrect", ["ラテン文字の自動修正", "Autocorrect typos (Latin keyboards)", "Correzione automatica dei refusi (tastiere latine)"]),
                    ("enable_latin_auto_capitalization", ["文頭を自動で大文字に", "Auto-capitalization", "Maiuscole automatiche"]),
                    ("double_space_period", ["スペース2回でピリオド", "Double-space for period", "Doppio spazio per il punto"]),
                ]
            }
            if language == "it" {
                contracts.append(("italian_auto_accent_on_space", ["スペースでアクセントを自動補正（イタリア語）", "Auto-accent on space (Italian)", "Accento automatico con lo spazio (italiano)"]))
            }
            for (key, labels) in contracts {
                let toggle = mainApp.switches.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
                for direction in [false, true] {
                    for _ in 0..<8 where !toggle.exists || !toggle.isHittable {
                        if direction { mainApp.swipeUp() } else { mainApp.swipeDown() }
                        let alert = mainApp.alerts.firstMatch
                        if alert.exists, alert.buttons.firstMatch.exists { alert.buttons.firstMatch.tap() }
                    }
                }
                guard toggle.exists, toggle.isHittable, toggle.value as? String == "0" else {
                    throw BenchError.configuration("Literal scenario prerequisite: seed \(key)=false; observed \(toggle.exists ? String(describing: toggle.value) : "missing")")
                }
                attachScreenshot("62-\(language)-seed-\(key)-off")
            }
            let field = try prepareKeyboard(fieldPlaceholder: "textarea-field", keyboard: "copaky", language: language)
            guard field.exists, field.value is String else { throw BenchError.missingElement("Readable textarea fixture is required") }
            try clearBenchField(field, keyboard: "copaky")
            func checkpoint(_ name: String, _ expected: String) throws {
                let deadline = Date().addingTimeInterval(3)
                repeat {
                    if currentFieldValue(field) == expected { break }
                    wait(0.2)
                } while Date() < deadline
                let observed = currentFieldValue(field)
                checkpoints.append(["step": name, "expected": expected, "observed_raw": observed, "taps": taps, "matched": observed == expected])
                attachScreenshot("62-\(language)-\(name)")
                guard observed == expected else { throw BenchError.input("\(name): expected \(expected.debugDescription), observed \(observed.debugDescription)") }
            }
            func literal(_ value: String) throws {
                for character in value {
                    if character == " " { try tapSpace(keyboard: "copaky") }
                    else if character == "\n" {
                        taps += try tapNewline(field: field)
                        continue
                    } else { try tapLatinCharacter(character, keyboard: "copaky") }
                    taps += 1
                }
            }
            func commitKana(_ reading: String) throws {
                let prefix = currentFieldValue(field)
                taps += try tapFlickString(reading)
                let expected = prefix + reading
                let typingDeadline = Date().addingTimeInterval(3)
                repeat {
                    if currentFieldValue(field) == expected { break }
                    wait(0.2)
                } while Date() < typingDeadline
                guard currentFieldValue(field) == expected else {
                    throw BenchError.input("Literal kana before confirmation: expected \(expected.debugDescription), observed \(currentFieldValue(field).debugDescription)")
                }
                // Copaky: UnifiedEnterKeyModel.complete performs .enter; with live conversion OFF,
                // InputManager.enterCandidate commits composingText.convertTarget literally.
                // Copaky: ライブ変換OFFでは「確定」が入力中のかなをそのまま確定する。
                guard let confirm = visibleKeyboardControl(labels: ["確定"]) else {
                    throw BenchError.missingElement("Actual Japanese confirmation key is missing")
                }
                confirm.tap()
                taps += 1
                let commitDeadline = Date().addingTimeInterval(3)
                repeat {
                    if currentFieldValue(field) == expected, visibleKeyboardControl(labels: returnLabels) != nil { return }
                    wait(0.2)
                } while Date() < commitDeadline
                throw BenchError.input("Japanese confirmation must retain \(expected.debugDescription) and expose the actual return key; observed \(currentFieldValue(field).debugDescription)")
            }
            if language == "ja" {
                try commitKana("あいう")
                try checkpoint("kana", "あいう")
                try literal("  ")
                try checkpoint("two-spaces", "あいう  ")
                try commitKana("かきく")
                try checkpoint("second-word", "あいう  かきく")
                guard let punctuation = visibleStaticText(labels: ["､｡?!"], keyboard: "copaky") else { throw BenchError.missingElement("Japanese punctuation key missing") }
                let start = safari.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: punctuation.frame.midX - safari.frame.minX, dy: punctuation.frame.midY - safari.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -52, dy: 0)))
                taps += 1
                try checkpoint("punctuation-before-newline", "あいう  かきく。")
                try literal("\n")
                try checkpoint("punctuation-newline", "あいう  かきく。\n")
                try commitKana("さ")
                try checkpoint("before-delete", "あいう  かきく。\nさ")
            } else {
                let first = language == "it" ? "ciao" : "hello"
                let second = language == "it" ? "mondo" : "world"
                let line = language == "it" ? "riga" : "next"
                try literal(first)
                try checkpoint("first-word", first)
                try literal("  ")
                try checkpoint("two-spaces", first + "  ")
                try literal(second + ".")
                try checkpoint("punctuation-before-newline", first + "  " + second + ".")
                try literal("\n")
                try checkpoint("punctuation-newline", first + "  " + second + ".\n")
                try literal(line + "!")
                try checkpoint("before-delete", first + "  " + second + ".\n" + line + "!")
            }
            let beforeDelete = currentFieldValue(field)
            guard let delete = deleteKey(keyboard: "copaky"), delete.isHittable else { throw BenchError.missingElement("Real delete key missing") }
            delete.tap()
            taps += 1
            let deleted = String(beforeDelete.dropLast())
            try checkpoint("deleted-one-character", deleted)
            if language == "ja" { try commitKana("た") } else { try literal("a") }
            try checkpoint("edited-final", deleted + (language == "ja" ? "た" : "a"))
        } catch let failure {
            error = String(describing: failure)
        }
        _ = emitJSON(["meta": benchmarkMeta(keyboard: "copaky", language: language, autocorrect: false, tsv: "built-in literal scenario"), "checkpoints": checkpoints, "taps": taps, "ms": elapsedMilliseconds(since: started), "error": error.map { $0 as Any } ?? NSNull()], name: "real-typing-\(language).json")
        attachScreenshot("62-\(language)-final")
        XCTAssertNil(error, "Real typing scenario failed: \(error ?? "")")
        XCTAssertEqual(checkpoints.count, language == "ja" ? 8 : 7, "Every exact checkpoint must execute")
    }

    private func tapNewline(field: XCUIElement) throws -> Int {
        // Copaky: a composing word exposes Confirm, whose action is commit rather than newline.
        // Copaky: 未確定文字列の「確定」は改行ではない。確定後の実際の改行キーを別に押す。
        let before = currentFieldValue(field)
        var taps = 0
        if let confirm = visibleKeyboardControl(labels: ["確定", "Complete", "Conferma"]) {
            confirm.tap()
            taps += 1
            attachScreenshot("62-\(requestedLanguage)-composition-confirmed-before-newline")
        }
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if let newline = visibleKeyboardControl(labels: returnLabels + ["arrow.turn.down.left"]) {
                guard currentFieldValue(field) == before else {
                    throw BenchError.input("Confirm before newline changed literal text: \(currentFieldValue(field).debugDescription)")
                }
                newline.tap()
                return taps + 1
            }
            wait(0.2)
        } while Date() < deadline
        throw BenchError.missingElement("Actual newline key missing after \(taps) composition-confirmation tap(s)")
    }

    // Copaky: seeded-history reuse only; this does not qualify clipboard capture or persistence.
    // Copaky: シード済み履歴の再利用だけを確認し、取得・永続化の証明にはしない。
    func test63_clipboardReuseScenario() throws {
        let clips = ["Il tuo codice di verifica è 482913", "Ci prendiamo un caffè questa settimana?"]
        var checkpoints: [[String: Any]] = []
        var actions: [String] = []
        var error: String?
        let started = Date()
        do {
            guard environmentValue("COPAKY_CLIPBOARD_PRESEEDED") == "1" else {
                throw BenchError.configuration("HOLD: COPAKY_CLIPBOARD_PRESEEDED=1 is required; seed signed shared history with --seed-clipboard it")
            }
            guard requestedKeyboard == "copaky", requestedLanguage == "it" else {
                throw BenchError.configuration("Clipboard reuse scenario requires COPAKY_BENCH_KEYBOARD=copaky and COPAKY_BENCH_LANGUAGE=it")
            }
            let field = try prepareKeyboard(fieldPlaceholder: "textarea-field", keyboard: "copaky", language: "it")
            guard field.exists, field.value is String else { throw BenchError.missingElement("Readable textarea fixture is required") }
            try clearBenchField(field, keyboard: "copaky")
            func checkpoint(_ name: String, _ expected: String) throws {
                let deadline = Date().addingTimeInterval(3)
                repeat {
                    if currentFieldValue(field) == expected { break }
                    wait(0.2)
                } while Date() < deadline
                let observed = currentFieldValue(field)
                checkpoints.append(["step": name, "expected": expected, "observed_raw": observed, "matched": observed == expected])
                attachScreenshot("63-\(name)")
                guard observed == expected else { throw BenchError.input("\(name): expected \(expected.debugDescription), observed \(observed.debugDescription)") }
            }
            func openHistory() throws {
                guard let numbers = visibleKeyboardControl(labels: ["123", "numbers", "Numbers", "numeri", "Numeri", "数字", "textformat.123", "textformat.numbers"]) else {
                    throw BenchError.missingElement("HOLD: visible Latin numbers shortcut is missing")
                }
                numbers.press(forDuration: 1.2)
                actions.append("long-press Latin numbers shortcut")
                let back = safari.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "copaky_clipboard_back")).firstMatch
                guard back.waitForExistence(timeout: 4), back.isHittable,
                      let frame = keyboardFrame(for: "copaky"), self.frame(back.frame, isInside: frame) else {
                    throw BenchError.missingElement("HOLD: Copaky clipboard panel did not open from the real shortcut")
                }
                attachScreenshot("63-history-open-\(actions.count)")
            }
            func pasteClip(_ clip: String) throws {
                let tiles = safari.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "copaky_clipboard_text_tile", clip))
                guard tiles.firstMatch.waitForExistence(timeout: 4), let frame = keyboardFrame(for: "copaky") else {
                    throw BenchError.missingElement("HOLD: seeded Unicode clipboard tile is missing: \(clip)")
                }
                let viewport = frame.intersection(safari.frame)
                for attempt in 0...3 {
                    if let tile = tiles.allElementsBoundByIndex.prefix(12).first(where: {
                        $0.exists && $0.isHittable && self.frame($0.frame, isInside: frame)
                            && viewport.insetBy(dx: -1, dy: -1).contains($0.frame)
                    }) {
                        tile.tap()
                        actions.append("tap clipboard tile: \(clip)")
                        return
                    }
                    guard attempt < 3, let target = tiles.allElementsBoundByIndex.prefix(12).first(where: { $0.exists }) else { break }
                    let targetFrame = target.frame
                    guard targetFrame.height > 1, viewport.width > 80,
                          targetFrame.minY >= viewport.minY, targetFrame.maxY <= viewport.maxY,
                          targetFrame.minX < viewport.minX || targetFrame.maxX > viewport.maxX else { break }
                    // Copaky: ClipboardSection is a horizontal ScrollView/LazyHStack. Drag only
                    // within this tile's row; never scroll the page or tap a clipped tile.
                    // Copaky: 対象タイルの水平スクロール行だけを実際にドラッグする。
                    let left = viewport.minX + 24
                    let right = viewport.maxX - 24
                    let scrollLeft = targetFrame.maxX > viewport.maxX
                    let origin = safari.coordinate(withNormalizedOffset: .zero)
                    let start = origin.withOffset(CGVector(dx: (scrollLeft ? right : left) - safari.frame.minX, dy: targetFrame.midY - safari.frame.minY))
                    let end = origin.withOffset(CGVector(dx: (scrollLeft ? left : right) - safari.frame.minX, dy: targetFrame.midY - safari.frame.minY))
                    start.press(forDuration: 0.05, thenDragTo: end)
                    actions.append("swipe \(scrollLeft ? "left" : "right") in clipboard tile row; attempt=\(attempt + 1)")
                    wait(0.4)
                    attachScreenshot("63-tile-row-scroll-\(attempt + 1)")
                }
                throw BenchError.missingElement("HOLD: seeded clipboard tile is not entirely visible and hittable after at most three horizontal row gestures: \(clip)")
            }
            func backToLatin() throws {
                let back = safari.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "copaky_clipboard_back")).firstMatch
                guard back.exists, back.isHittable, let frame = keyboardFrame(for: "copaky"), self.frame(back.frame, isInside: frame) else {
                    throw BenchError.missingElement("HOLD: visible Copaky clipboard back control missing")
                }
                back.tap()
                actions.append("tap clipboard back")
                wait(0.4)
                // Copaky: observe the actual Back result; never switch tabs to repair it here.
                // Copaky: 戻る操作の結果を読み取りだけで検証し、タブ切替で修復しない。
                let deadline = Date().addingTimeInterval(3)
                var observedLanguage = copakyLanguageSwitchState()?.current ?? "missing"
                actions.append("clipboard back initial language=\(observedLanguage)")
                repeat {
                    observedLanguage = copakyLanguageSwitchState()?.current ?? "missing"
                    if let keyboardFrame = keyboardInputViewFrame(of: safari) {
                        func visible(_ labels: [String]) -> Bool {
                            safari.staticTexts.matching(NSPredicate(format: "label IN %@", labels))
                                .allElementsBoundByIndex.prefix(20).contains {
                                    $0.exists && $0.isHittable && self.frame($0.frame, isInside: keyboardFrame)
                                }
                        }
                        if observedLanguage == "IT", visible(["q", "Q"]), visible(latinSpaceLabels) {
                            attachScreenshot("63-back-to-latin-\(actions.count)")
                            return
                        }
                    }
                    wait(0.2)
                } while Date() < deadline
                actions.append("clipboard back failed language=\(observedLanguage)")
                throw BenchError.input("Clipboard back did not restore visible Italian Latin keys; observed language=\(observedLanguage)")
            }
            try openHistory()
            try pasteClip(clips[0])
            try checkpoint("first-unicode-paste", clips[0])
            try backToLatin()
            try tapSpace(keyboard: "copaky")
            actions.append("tap Latin space")
            try checkpoint("literal-space-after-paste", clips[0] + " ")
            let newlineTaps = try tapNewline(field: field)
            actions.append("tap actual newline; enter-control taps=\(newlineTaps)")
            let prefix = clips[0] + " \n"
            try checkpoint("newline-after-paste", prefix)
            try openHistory()
            try pasteClip(clips[1])
            try checkpoint("second-unicode-paste", prefix + clips[1])
            try backToLatin()
            for character in "ab" {
                try tapLatinCharacter(character, keyboard: "copaky")
                actions.append("tap Latin letter \(character)")
            }
            try checkpoint("literal-typing-after-second-paste", prefix + clips[1] + "ab")
        } catch let failure {
            error = String(describing: failure)
        }
        _ = emitJSON(["meta": benchmarkMeta(keyboard: "copaky", language: "it", autocorrect: nil, tsv: "seeded Unicode clipboard reuse"), "scope": "seeded-history reuse; capture, persistence and OS Full Access not qualified", "actions": actions, "checkpoints": checkpoints, "ms": elapsedMilliseconds(since: started), "error": error.map { $0 as Any } ?? NSNull()], name: "clipboard-reuse-it.json")
        attachScreenshot("63-final")
        XCTAssertNil(error, "Clipboard reuse scenario failed: \(error ?? "")")
        XCTAssertEqual(checkpoints.count, 5, "Every clipboard reuse checkpoint must execute")
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
                parseError: row.columns[0].isEmpty || row.columns[1].isEmpty ? "empty expected/noisy text at TSV line \(row.line)" : nil
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
        keyboard: String,
        onFixture: (PhraseResult) -> Void
    ) -> [PhraseResult] where C.Element == LatinFixture {
        fixtures.map { fixture in
            attachScreenshot("60-latin-fixture-\(fixture.id)-before")
            let tree = XCTAttachment(string: safari.debugDescription)
            tree.name = "60-latin-fixture-\(fixture.id)-tree-before"
            tree.lifetime = .keepAlways
            add(tree)
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
                    let candidates = waitForCandidates(keyboard: keyboard, timeout: 1)
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
            let final = currentFieldValue(field)
            // Each benchmark word deliberately taps a final space; preserve it in raw evidence.
            if phraseError == nil, final != fixture.expected + " " {
                phraseError = "final_mismatch"
            }
            let observation = PhraseResult(
                id: fixture.id,
                block: fixture.block,
                op: fixture.op,
                expected: fixture.expected,
                noisy: fixture.noisy,
                final: final,
                expectedRaw: fixture.expected + " ",
                taps: taps,
                milliseconds: elapsedMilliseconds(since: started),
                error: phraseError,
                words: words
            )
            onFixture(observation)
            return observation
        }
    }

    private func runJapaneseFixtures<C: Collection>(
        _ fixtures: C,
        field: XCUIElement,
        keyboard: String,
        onFixture: (PhraseResult) -> Void
    ) -> [PhraseResult] where C.Element == JapaneseFixture {
        fixtures.map { fixture in
            attachScreenshot("60-japanese-fixture-\(fixture.id)-before")
            let tree = XCTAttachment(string: safari.debugDescription)
            tree.name = "60-japanese-fixture-\(fixture.id)-tree-before"
            tree.lifetime = .keepAlways
            add(tree)
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
                    if candidates.isEmpty {
                        throw BenchError.missingElement("INFRA_CANDIDATE_OBSERVATION_UNAVAILABLE at segment \(index)")
                    }
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
            let observation = PhraseResult(
                id: fixture.id,
                block: "JA",
                op: "convert",
                expected: fixture.expected,
                noisy: fixture.reading,
                final: final,
                expectedRaw: fixture.expected,
                taps: taps,
                milliseconds: elapsedMilliseconds(since: started),
                error: phraseError,
                words: words
            )
            onFixture(observation)
            return observation
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
        return visibleKeyboardControl(labels: deleteLabels + ["delete.left", "delete.backward"])
    }

    private func tapSpace(keyboard: String) throws {
        let key: XCUIElement
        if keyboard == "apple" {
            key = safari.keyboards.firstMatch.keys.matching(NSPredicate(format: "label IN %@", latinSpaceLabels)).firstMatch
        } else {
            guard let space = visibleStaticText(labels: latinSpaceLabels, keyboard: keyboard) else { throw BenchError.missingElement("Visible Copaky space key is missing") }
            key = space
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
        // Copaky: the Latin letter tab has no period after F-07; use test38's numbers path.
        // Copaky: F-07以後の文字タブにピリオドはない。test38と同じ数字タブを使う。
        guard let numbers = visibleKeyboardControl(labels: ["123", "numbers", "Numbers", "numeri", "Numeri", "数字", "textformat.123", "textformat.numbers"]) else {
            throw BenchError.missingElement("Latin numbers key is missing")
        }
        numbers.tap()
        wait(0.4)
        guard let punctuation = visibleStaticText(labels: [target], keyboard: "copaky") else {
            throw BenchError.unsupportedCharacter(character)
        }
        punctuation.tap()
        wait(0.2)
        guard let frame = keyboardFrame(for: "copaky") else { throw BenchError.missingElement("Numbers keyboard disappeared") }
        let query = safari.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["ABC", "ITA", "あいう"]))
        let back = query.allElementsBoundByIndex.filter {
            guard $0.exists else { return false }
            let measured = $0.frame
            guard self.frame(measured, isInside: frame), safari.frame.insetBy(dx: -1, dy: -1).contains(measured) else { return false }
            return $0.isHittable
        }.min { $0.frame.minX < $1.frame.minX }
        guard let back else { throw BenchError.missingElement("Numbers-tab language/back key is missing") }
        back.tap()
        wait(0.4)
        guard switchToLatinQwertyTab(in: safari) else { throw BenchError.input("Numbers tab did not return to Latin") }
    }

    private func visibleKeyboardControl(labels: [String]) -> XCUIElement? {
        guard let frame = keyboardFrame(for: "copaky") else { return nil }
        let query = safari.descendants(matching: .any).matching(NSPredicate(format: "label IN %@ OR identifier IN %@", labels, labels))
        return query.allElementsBoundByIndex.prefix(30).first {
            guard $0.exists else { return false }
            let measured = $0.frame
            guard self.frame(measured, isInside: frame), safari.frame.insetBy(dx: -1, dy: -1).contains(measured) else { return false }
            return $0.isHittable
        }
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
            guard element.exists else { continue }
            let measured = element.frame
            guard self.frame(measured, isInside: frame), safari.frame.insetBy(dx: -1, dy: -1).contains(measured) else { continue }
            if element.isHittable { return element }
        }
        return nil
    }

    private func candidateRegion(keyboard: String) -> CGRect? {
        guard keyboard == "copaky", let input = keyboardFrame(for: keyboard),
              safari.frame.insetBy(dx: -1, dy: -1).contains(input) else { return nil }
        let anchors = safari.staticTexts.matching(NSPredicate(format: "label IN %@", ["q", "Q", "あ", "か", "さ"]))
        var provenCells: [String: CGRect] = [:]
        for anchor in anchors.allElementsBoundByIndex.prefix(20) {
            guard anchor.exists else { continue }
            let measured = anchor.frame
            guard isKeyCell(measured, in: input, letter: true),
                  safari.frame.insetBy(dx: -1, dy: -1).contains(measured), anchor.isHittable else { continue }
            let label = anchor.label
            if let previous = provenCells[label], previous.width * previous.height >= measured.width * measured.height { continue }
            provenCells[label] = measured
        }
        guard let keyTop = provenCells.values.map(\.minY).min(), keyTop > input.minY + 1 else { return nil }
        // Copaky: inputView is an AX placeholder; candidates render in a sibling window. Admit
        // only visible text above a proved physical first-row cell, never glyph/parent transforms.
        // Copaky: AXのinputViewに子要素がなくても、実キーより上の表示領域だけを読む。
        return CGRect(x: input.minX, y: input.minY, width: input.width, height: keyTop - input.minY - 1)
    }

    private func candidateLabels(keyboard: String) -> [String] {
        guard let region = candidateRegion(keyboard: keyboard) else { return [] }
        var candidates: [(String, CGFloat)] = []
        var observations: [[String: Any]] = []
        // Copaky: ResultBar exposes its textual candidates as Button(action:label:) elements.
        // Copaky: ResultBarの文字候補はStaticTextではなくButtonとして公開される。
        // Bind by AX identity: repeated index resolution omitted visible candidates on iOS 26.5.
        // インデックス再解決による表示候補の欠落を避け、AX要素の識別情報に結び付ける。
        let texts = safari.buttons.allElementsBoundByAccessibilityElement
        for element in texts.prefix(240) {
            guard element.exists else { continue }
            let measured = element.frame
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let inside = self.frame(measured, isInside: region) && safari.frame.insetBy(dx: -1, dy: -1).contains(measured)
            let hittable = inside && element.isHittable
            observations.append(["label": label, "identifier": element.identifier, "frame": NSCoder.string(for: measured), "inside": inside, "hittable": hittable])
            guard inside, hittable, !["chevron.down", "chevron.up"].contains(element.identifier) else { continue }
            guard !label.isEmpty else { continue }
            candidates.append((label, measured.minX))
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["region": NSCoder.string(for: region), "buttons": observations], options: [.prettyPrinted, .sortedKeys]) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "decoder-candidate-observation-\(UUID().uuidString).json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        var seen = Set<String>()
        return candidates.sorted { $0.1 < $1.1 }.compactMap { label, _ in
            guard !["写", "取り消す", "Annulla", "Undo", "お知らせ", "逆順", "chevron.down", "chevron.up"].contains(label) else { return nil }
            return seen.insert(label).inserted ? label : nil
        }
    }

    private func waitForCandidates(keyboard: String, timeout: TimeInterval) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var previous: [String] = []
        var observations = 0
        repeat {
            let labels = candidateLabels(keyboard: keyboard)
            observations += 1
            if !labels.isEmpty, labels == previous { return labels }
            previous = labels
            wait(0.2)
            // Copaky: one AX snapshot may exceed the polling window. Allow its bounded second
            // observation before classifying a visible list as unavailable.
            // Copaky: AX取得が待機時間を超えても、最初の候補リストの確認を一度だけ許す。
        } while observations < 3 && (Date() < deadline || (observations == 1 && !previous.isEmpty))
        return [] // Unstable/missing candidates are not a measured candidate list.
    }

    private func candidateElement(label: String, keyboard: String) -> XCUIElement? {
        guard let region = candidateRegion(keyboard: keyboard) else { return nil }
        let texts = safari.buttons.matching(NSPredicate(format: "label == %@", label))
        for index in 0..<min(texts.count, 20) {
            let element = texts.element(boundBy: index)
            guard element.exists else { continue }
            let measured = element.frame
            guard self.frame(measured, isInside: region), safari.frame.insetBy(dx: -1, dy: -1).contains(measured), element.isHittable else { continue }
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

//
//  InputManager.swift
//  Keyboard
//
//  Created by ensan on 2022/12/30.
//  Copyright © 2022 ensan. All rights reserved.
//

import AzooKeyUtils
import CoreText
import CustardKit
import FoundationModels
import KanaKanjiConverterModule
import KeyboardExtensionUtils
import KeyboardViews
import os
import OrderedCollections
import SwiftUtils
import UIKit

final class InputManager {
#if DEBUG
    private static let autocorrectLog = OSLog(
        subsystem: "com.pettipol.copaky.keyboard",
        category: "Autocorrect"
    )
#endif
    // 入力中の文字列を管理する構造体
    private(set) var composingText = ComposingText()
    // 表示される文字列を管理するクラス
    private(set) var displayedTextManager: DisplayedTextManager
    // Copaky: retain the host proxy separately so auto-accent can respect its input traits even when
    // DisplayedTextManager temporarily prefers an in-keyboard text field.
    // Copaky: キーボード内入力欄への切替中もホスト側の入力属性を確認できるよう保持する。
    private var mainTextDocumentProxy: (any UITextDocumentProxy)?
    private var activeTextDocumentProxyPreference: AnyTextDocumentProxy.Preference = .main
    private struct LatinSpaceCorrection {
        let original: String
        let corrected: String
        let undoEligible: Bool
    }
    private struct LastLatinAutocorrection {
        let documentIdentifier: UUID
        let original: String
        let corrected: String
        let leftContextAfterCorrection: String
        let rightContextAfterCorrection: String
    }
    private struct LastDoubleSpacePeriod {
        let documentIdentifier: UUID
        let leftContextAfterReplacement: String
        let rightContextAfterReplacement: String
    }
    private struct LastLatinSpaceTap {
        let documentIdentifier: UUID
        let uptime: TimeInterval
        let leftContext: String
        let rightContext: String
    }
    // Copaky: one-shot stock-keyboard-style undo. It never survives another key or cursor move.
    // Copaky: 直後の削除キー1回だけで元の語へ戻す一時状態。他の操作では必ず破棄する。
    private var lastLatinAutocorrection: LastLatinAutocorrection?
    private var lastDoubleSpacePeriod: LastDoubleSpacePeriod?
    private var lastLatinSpaceTap: LastLatinSpaceTap?
    // TODO: displayedTextManagerとliveConversionManagerを何らかの形で統合したい
    // ライブ変換を管理するクラス
    var liveConversionManager: LiveConversionManager
    // (ゼロクエリの)予測変換を管理するクラス
    var predictionManager = PredictionManager()
    // セレクトされているか否か、現在入力中の文字全体がセレクトされているかどうかである。
    // TODO: isSelectedはdisplayedTextManagerが持っているべき
    var isSelected = false
    /// かな漢字変換を受け持つ変換器。
    @MainActor private lazy var kanaKanjiConverter = KanaKanjiConverter(dicdataStore: DicdataStore(dictionaryURL: Self.dictionaryResourceURL))

    init() {
        @KeyboardSetting(.liveConversion) var liveConversion
        @KeyboardSetting(.markedTextSetting) var markedTextSetting

        self.displayedTextManager = DisplayedTextManager(isLiveConversionEnabled: liveConversion, isMarkedTextEnabled: markedTextSetting != .disabled)
        self.liveConversionManager = LiveConversionManager(enabled: liveConversion)
    }
    // キーボードの言語
    private var keyboardLanguage: KeyboardLanguage = .ja_JP
    @MainActor func setKeyboardLanguage(_ value: KeyboardLanguage) {
        self.keyboardLanguage = value
        self.kanaKanjiConverter.setKeyboardLanguage(value)
    }

    // 再変換機能の提供のために用いる辞書
    private var rubyLog: OrderedDictionary<String, String> = [:]

    // 変換結果の通知用関数
    private var updateResult: (((inout ResultModel) -> Void) -> Void)?

    private var liveConversionEnabled: Bool {
        liveConversionManager.enabled && !self.isSelected
    }

    func getEnterKeyState() -> RoughEnterKeyState {
        if !self.isSelected && !self.composingText.isEmpty {
            return .complete
        } else {
            return .return
        }
    }

    @MainActor func getSurroundingText() -> (leftText: String, center: String, rightText: String) {
        let left = adjustLeftString(self.displayedTextManager.documentContextBeforeInput(ignoreComposition: true) ?? "")
        let center = self.displayedTextManager.selectedText ?? ""
        let right = self.displayedTextManager.documentContextAfterInput ?? ""

        return (left, center, right)
    }

    func getTextChangedCount() -> Int {
        self.displayedTextManager.getTextChangedCount()
    }

    func getComposingText() -> ComposingText {
        self.composingText
    }

    func getCandidate(for forms: [CharacterForm]) -> Candidate {
        var text = self.composingText.convertTarget
        for form in forms {
            switch form {
            case .hiragana:
                text = text.toHiragana()
            case .katakana:
                text = text.toKatakana()
            case .halfwidthKatakana:
                // Copaky: the transform is constant and the input is a valid String, so nil is not
                // expected — but a keyboard extension must not crash on host-app text either way.
                // 変換は定数で入力は正当な String なので nil は想定外だが、拡張はホストの文字列で落ちてはならない。
                let katakana = text.toKatakana()
                text = katakana.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? katakana
            case .uppercase:
                text = text.uppercased()
            case .lowercase:
                text = text.lowercased()
            }
        }
        return .init(text: text, value: 0, composingCount: .surfaceCount(self.composingText.convertTargetCursorPosition), lastMid: MIDData.一般.mid, data: [])
    }

    private static let dictionaryResourceURL = Bundle.main.bundleURL.appendingPathComponent("Dictionary", isDirectory: true)
    private static let memoryDirectoryURL = (try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? sharedContainerURL
    // Copaky: fail-soft — fall back to the keyboard's temporary directory instead of crashing if the
    // App Group container is unavailable (e.g. provisioning/entitlement edge cases). 起動時クラッシュ回避。
    private static let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupKey) ?? FileManager.default.temporaryDirectory
    // Copaky: Zenzai gguf model weights are no longer bundled (feature deferred to v2).

    @MainActor private func getConvertRequestOptions(inputStylePreference: InputStyle? = nil) -> ConvertRequestOptions {
        let requireJapanesePrediction: Bool
        let requireEnglishPrediction: Bool
        switch (isSelected, inputStylePreference ?? .direct) {
        case (true, _):
            requireJapanesePrediction = false
            requireEnglishPrediction = false
        case (false, .direct):
            requireJapanesePrediction = true
            requireEnglishPrediction = true
        case (false, .roman2kana):
            requireJapanesePrediction = keyboardLanguage == .ja_JP
            requireEnglishPrediction = keyboardLanguage == .en_US
        case (false, .mapped):
            requireJapanesePrediction = keyboardLanguage == .ja_JP
            requireEnglishPrediction = false
        }
        @KeyboardSetting(.typographyLetter) var typographyLetterCandidate
        @KeyboardSetting(.englishCandidate) var englishCandidateInRoman2KanaInput
        @KeyboardSetting(.learningType) var learningType

        var providers: [any SpecialCandidateProvider] = [.calendar, .commaSeparatedNumber, .emailAddress, .timeExpression, .unicode, .version]
        if typographyLetterCandidate {
            providers.append(.typography)
        }

        // Copaky: Zenzai disabled (feature deferred to v2) — always pass .off to the converter engine.
        let zenzaiMode: ConvertRequestOptions.ZenzaiMode = .off

        return ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: .autoMix,
            requireEnglishPrediction: .autoMix,
            keyboardLanguage: keyboardLanguage,
            // KeyboardSettingsを注入
            englishCandidateInRoman2KanaInput: englishCandidateInRoman2KanaInput,
            fullWidthRomanCandidate: true,
            halfWidthKanaCandidate: true,
            learningType: learningType,
            maxMemoryCount: 65536,
            shouldResetMemory: MemoryResetCondition.shouldReset(),
            memoryDirectoryURL: Self.memoryDirectoryURL,
            sharedContainerURL: Self.sharedContainerURL,
            textReplacer: self.textReplacer,
            specialCandidateProviders: providers,
            zenzaiMode: zenzaiMode,
            metadata: .init(versionString: "Copaky version " + (SharedStore.currentAppVersion?.description ?? "Unknown")))
    }

    @MainActor private func getConvertRequestOptionsForPrediction() -> (ConvertRequestOptions, denylist: Set<String>) {
        // 絵文字変換が無効になっている場合、予測変換からも絵文字を抜く
        var options = getConvertRequestOptions()
        @KeyboardSetting(.additionalSystemDictionarySetting) var additionalSystemDictionarySetting
        if additionalSystemDictionarySetting.systemDictionarySettings[.emoji]?.enabled == false {
            options.textReplacer = .empty
        }
        return (options, additionalSystemDictionarySetting.systemDictionarySettings[.emoji]?.denylist ?? [])
    }

    private func updateLog(candidate: Candidate) {
        for data in candidate.data {
            // 「感謝する: カンシャスル」→を「感謝: カンシャ」に置き換える
            var word = data.word.toHiragana()
            var ruby = data.ruby.toHiragana()

            // wordのlastがrubyのlastである時、この文字は仮名なので
            while !word.isEmpty && word.last == ruby.last {
                word.removeLast()
                ruby.removeLast()
            }
            while !word.isEmpty && word.first == ruby.first {
                word.removeFirst()
                ruby.removeFirst()
            }
            if word.isEmpty {
                continue
            }
            // 一度消してから入れる(reorder)
            rubyLog.removeValue(forKey: word)
            rubyLog[word] = ruby
        }
        while rubyLog.count > 100 {  // 最大100個までログを取る
            rubyLog.removeFirst()
        }
        debug("rubyLog", rubyLog)
    }

    /// ルビ(ひらがな)を返す
    private func getRubyIfPossible(text: String) -> String? {
        // TODO: もう少しやりようがありそう、例えばログを見てひたすら置換し、最後にkanaだったらヨシ、とか？
        // ユーザがテキストを選択した場合、というやや強い条件が入っているので、パフォーマンスをあまり気にしなくても大丈夫
        // 長い文章を再変換しない、みたいな仮定も入れられる
        if let ruby = rubyLog[text] {
            return ruby.toHiragana()
        }
        // 長い文章は諦めてもらう
        if text.count > 20 {
            return nil
        }
        // {hiragana}*{known word}のパターンを救う
        do {
            for (word, ruby) in rubyLog where text.hasSuffix(word) {
                if text.dropLast(word.count).isKana {
                    return (text.dropLast(word.count) + ruby).toHiragana()
                }
            }
        }
        // {known word}{hiragana}*のパターンを救う
        do {
            for (word, ruby) in rubyLog where text.hasPrefix(word) {
                if text.dropFirst(word.count).isKana {
                    return (ruby + text.dropFirst(word.count)).toHiragana()
                }
            }
        }
        return nil
    }
    /// 置換機
    private var textReplacer = TextReplacer(emojiDataProvider: {
        // 読み込むファイルはバージョンごとに変更する必要がある
        if #available(iOS 26.4, *) {
            Bundle.main.bundleURL.appendingPathComponent("emoji_all_E17.0.txt", isDirectory: false)
        } else if #available(iOS 18.4, *) {
            Bundle.main.bundleURL.appendingPathComponent("emoji_all_E16.0.txt", isDirectory: false)
        } else {
            // in this case, always satisfies #available(iOS 17.4, *)
            Bundle.main.bundleURL.appendingPathComponent("emoji_all_E15.1.txt", isDirectory: false)
        }
    })

    @MainActor func setTextDocumentProxy(_ proxy: AnyTextDocumentProxy) {
        switch proxy {
        case .mainProxy, .ikTextFieldProxy:
            self.clearLastLatinAutocorrection()
            self.clearLastLatinSpaceTap()
        case let .preference(preference):
            let changed = switch (self.activeTextDocumentProxyPreference, preference) {
            case (.main, .ikTextField), (.ikTextField, .main): true
            default: false
            }
            if changed {
                self.clearLastLatinAutocorrection()
                self.clearLastLatinSpaceTap()
            }
            self.activeTextDocumentProxyPreference = preference
        }
        if case let .mainProxy(mainProxy) = proxy {
            self.mainTextDocumentProxy = mainProxy
        }
        self.displayedTextManager.setTextDocumentProxy(proxy)
    }

    func setUpdateResult(_ updateResult: (((inout ResultModel) -> Void) -> Void)?) {
        self.updateResult = updateResult
    }

    @MainActor
    func consumeExpectedEdit(beforeLeft: String, beforeCenter: String, beforeRight: String, afterLeft: String, afterCenter: String, afterRight: String) -> ExpectedEditTracker.Consumption {
        let before = ObservedTextState(left: beforeLeft, center: beforeCenter, right: beforeRight)
        let after = ObservedTextState(left: afterLeft, center: afterCenter, right: afterRight)
        return self.displayedTextManager.consumeExpectedEdit(before: before, after: after)
    }

    /// 結果の更新
    func updateTextReplacementCandidates(left: String, center: String, right: String, target: [ConverterBehaviorSemantics.ReplacementTarget]) {
        let results = self.textReplacer.getReplacementCandidate(left: left, center: center, right: right, target: target)
        if let updateResult {
            updateResult {
                $0.setResults(results)
            }
        }
    }

    /// 検索結果の更新
    func getSearchResult(query: String, target: [ConverterBehaviorSemantics.ReplacementTarget]) -> [any ResultViewItemData] {
        let results = self.textReplacer.getSearchResult(query: query, target: target)
        return results
    }

    /// 絵文字候補のクリーニング
    @MainActor func cleaningEmojiPredictionCandidates(candidates: consuming [PostCompositionPredictionCandidate], denylist: Set<String>) -> [PostCompositionPredictionCandidate] {
        candidates.filter {
            // variation selectorを外す
            let normalized = String($0.text.unicodeScalars.filter { $0.value != 0xFE0F })
            // 1文字でもdenylistに含まれるものがあったらエラー
            return normalized.allSatisfy({!denylist.contains(String($0))})
        }

    }

    /// 確定直後に呼ぶ
    @MainActor func updatePostCompositionPredictionCandidates(candidate: Candidate) {
        let (options, denylist) = getConvertRequestOptionsForPrediction()
        var results = self.kanaKanjiConverter.requestPostCompositionPredictionCandidates(leftSideCandidate: candidate, options: options)
        results = self.cleaningEmojiPredictionCandidates(candidates: results, denylist: denylist)
        predictionManager.updateAfterComplete(candidate: candidate, textChangedCount: self.displayedTextManager.getTextChangedCount())
        if let updateResult {
            updateResult {
                $0.setPredictionResults(results)
            }
        }
    }

    /// 予測変換を選んだ後に呼ぶ
    @MainActor func postCompositionPredictionCandidateSelected(candidate: PostCompositionPredictionCandidate) {
        guard let lastUsedCandidate = predictionManager.getLastCandidate() else {
            return
        }
        self.kanaKanjiConverter.updateLearningData(lastUsedCandidate, with: candidate)
        let newCandidate = candidate.join(to: lastUsedCandidate)

        // 絵文字変換が無効になっている場合、予測変換からも絵文字を抜く
        let (options, denylist) = getConvertRequestOptionsForPrediction()
        var results = self.kanaKanjiConverter.requestPostCompositionPredictionCandidates(leftSideCandidate: newCandidate, options: options)
        results = self.cleaningEmojiPredictionCandidates(candidates: results, denylist: denylist)
        predictionManager.update(candidate: newCandidate, textChangedCount: self.displayedTextManager.getTextChangedCount())
        if let updateResult {
            updateResult {
                $0.setPredictionResults(results)
            }
        }
    }

    func resetPostCompositionPredictionCandidates() {
        if let updateResult {
            updateResult {
                $0.setPredictionResults([])
            }
        }
    }

    func resetPostCompositionPredictionCandidatesIfNecessary(textChangedCount: Int) {
        if predictionManager.shouldResetPrediction(textChangedCount: textChangedCount) {
            self.resetPostCompositionPredictionCandidates()
        }
    }

    /// `composingText`に入力されていた全体が変換された後に呼ばれる関数
    @MainActor private func conversionCompleted(candidate: Candidate) {
        // 予測変換を更新する
        self.updatePostCompositionPredictionCandidates(candidate: candidate)
    }

    /// 変換を選択した場合に呼ばれる
    @MainActor func complete(candidate: Candidate) {
        self.updateLog(candidate: candidate)
        self.composingText.prefixComplete(composingCount: candidate.composingCount)
        self.displayedTextManager.updateComposingText(composingText: self.composingText, completedPrefix: candidate.text, isSelected: self.isSelected)
        self.kanaKanjiConverter.updateLearningData(candidate)
        guard !self.composingText.isEmpty else {
            // ここで入力を停止する
            self.stopComposition()
            self.conversionCompleted(candidate: candidate)
            return
        }
        self.isSelected = false
        self.kanaKanjiConverter.setCompletedData(candidate)

        if liveConversionEnabled {
            self.liveConversionManager.updateAfterFirstClauseCompletion()
        }
        self.setResult()
    }

    @MainActor
    func completeAndStartNewComposition(candidate: Candidate, with text: String, simpleInsert: Bool = false, inputStyle: InputStyle) -> Bool {
        guard !self.isSelected, !self.shouldDirectInsert(text: text, simpleInsert: simpleInsert) else {
            return false
        }

        self.updateLog(candidate: candidate)
        var composingText = self.composingText
        composingText.prefixComplete(composingCount: candidate.composingCount)
        self.kanaKanjiConverter.updateLearningData(candidate)

        if composingText.isEmpty {
            self.liveConversionManager.stopComposition()
            self.kanaKanjiConverter.stopComposition()
            self.conversionCompleted(candidate: candidate)
        } else {
            self.kanaKanjiConverter.setCompletedData(candidate)
            if liveConversionEnabled {
                self.liveConversionManager.updateAfterFirstClauseCompletion()
            }
        }

        self.isSelected = false
        composingText.insertAtCursorPosition(text, inputStyle: inputStyle)
        self.composingText = composingText
        self.displayedTextManager.updateComposingText(completedPrefix: candidate.text, composingText: composingText, newLiveConversionText: nil)
        self.setResult()
        return true
    }

    /// 入力を停止する。DisplayedTextには特に何もしない。
    @MainActor func stopComposition() {
        self.clearLastLatinAutocorrection()
        self.clearLastLatinSpaceTap()
        self.composingText.stopComposition()
        self.displayedTextManager.stopComposition()
        self.liveConversionManager.stopComposition()
        self.kanaKanjiConverter.stopComposition()

        self.isSelected = false

        if let updateResult {
            updateResult {
                $0.setResults([])
            }
        }

        @KeyboardSetting(.liveConversion) var liveConversion
        @KeyboardSetting(.markedTextSetting) var markedTextSetting

        self.displayedTextManager.updateSettings(isLiveConversionEnabled: liveConversion, isMarkedTextEnabled: markedTextSetting != .disabled)
    }

    @MainActor func closeKeyboard() {
        debug("closeKeyboard: キーボードが閉じます")
        self.clearLastLatinAutocorrection()
        self.clearLastLatinSpaceTap()
        self.activeTextDocumentProxyPreference = .main
        self.displayedTextManager.setTextDocumentProxy(.preference(.main))
        self.kanaKanjiConverter.commitUpdateLearningData()
        self.kanaKanjiConverter.updateUserDictionaryURL(Self.sharedContainerURL, forceReload: true)
        self.displayedTextManager.closeKeyboard()
        _ = self.enter()
    }

    // Copaky: build the same plain commit candidate with an optional visible-text override, used by
    // auto-accent while preserving its composing count, dictionary metadata, and logging path.
    // Copaky: アクセント補正でも入力数・辞書情報・学習経路を保つ確定候補を共通生成する。
    @MainActor private func enterCandidate(textOverride: String?) -> Candidate {
        let composingText = self.composingText.prefixToCursorPosition()
        if textOverride == nil, liveConversionEnabled, let _candidate = liveConversionManager.lastUsedCandidate {
            return _candidate
        }
        let committedText = textOverride ?? composingText.convertTarget
        return Candidate(
            text: committedText,
            value: -18,
            composingCount: .inputCount(composingText.input.count),
            lastMid: MIDData.一般.mid,
            data: [
                DicdataElement(
                    word: committedText,
                    ruby: committedText.toKatakana(),
                    cid: CIDData.固有名詞.cid,
                    mid: MIDData.一般.mid,
                    value: -18
                ),
            ]
        )
    }

    /// 「現在入力中として表示されている文字列で確定する」というセマンティクスを持った操作である。
    /// - parameters:
    ///  - shouldModifyDisplayedText: DisplayedTextを操作して良いか否か。`textDidChange`などの場合は操作してはいけない。
    @MainActor func enter(shouldModifyDisplayedText: Bool = true, requireSetResult: Bool = true, textOverride: String? = nil) -> [ActionType] {
        // selectedの場合、単に変換を止める
        if isSelected {
            self.stopComposition()
            return []
        }
        if self.composingText.isEmpty {
            return []
        }
        var candidate = self.enterCandidate(textOverride: textOverride)
        let actions = self.kanaKanjiConverter.getAppropriateActions(candidate)
        candidate.withActions(actions)
        candidate.parseTemplate()
        self.updateLog(candidate: candidate)
        if shouldModifyDisplayedText {
            self.composingText.prefixComplete(composingCount: candidate.composingCount)
            self.displayedTextManager.updateComposingText(composingText: self.composingText, completedPrefix: candidate.text, isSelected: self.isSelected)
        }
        if self.displayedTextManager.composingText.isEmpty {
            self.stopComposition()
            self.conversionCompleted(candidate: candidate)
        } else if requireSetResult {
            self.setResult()
        }
        return actions.map(\.action)
    }

    @MainActor func insertMainDisplayText(_ text: String) {
        self.displayedTextManager.insertMainDisplayText(text)
    }

    @MainActor func deleteSelection() {
        // 選択部分を削除する
        self.displayedTextManager.deleteBackward(count: 1)
        // 状態をリセットする
        self.composingText.stopComposition()
        self.kanaKanjiConverter.stopComposition()
        self.isSelected = false
    }

    /// テキスト入力を扱う関数
    /// - Parameters:
    ///   - text: 入力される関数
    ///   - requireSetResult: `View`のアップデートを、この呼び出しで実施するべきか。この後さらに別の呼び出しを行う場合は、`false`にする。
    ///   - simpleInsert: `ComposingText`を作るのではなく、直接文字を入力し、変換候補を表示しない。
    ///   - inputStyle: 入力スタイル
    @MainActor func input(
        text: String,
        requireSetResult: Bool = true,
        simpleInsert: Bool = false,
        inputStyle: InputStyle,
        isLatinQwertyTab: Bool = false
    ) {
        let inputUptime = ProcessInfo.processInfo.systemUptime
        if text == " ", self.replaceSecondLatinSpaceWithPeriodIfNeeded(
            at: inputUptime,
            isLatinQwertyTab: isLatinQwertyTab
        ) {
            return
        }
        self.clearLastLatinAutocorrection()
        if text != " " {
            self.clearLastLatinSpaceTap()
        }
        // 直接入力の条件
        if self.shouldDirectInsert(text: text, simpleInsert: simpleInsert) {
            // 必要に応じて確定する
            var correction: LatinSpaceCorrection?
            if !self.isSelected {
                // Copaky: A-01c remains first; B-04 generalizes the same space-time textOverride
                // commit for opt-in Italian/English typo correction.
                // Copaky: A-01c を優先し、同じ空白確定経路を伊英の誤字補正へ一般化する。
                correction = text == " " ? self.latinCorrectionForSpace() : nil
                _ = self.enter(textOverride: correction?.corrected)
            } else {
                self.stopComposition()
            }
            self.displayedTextManager.insertText(text)
            if let correction, correction.undoEligible {
                self.rememberLatinAutocorrection(correction)
            }
            self.rememberLatinSpaceTapIfEligible(
                text: text,
                at: inputUptime,
                isLatinQwertyTab: isLatinQwertyTab
            )
            return
        }
        // 直接入力にならない場合はまず選択部分を削除する
        if self.isSelected {
            // 選択部分を削除する
            self.deleteSelection()
        }
        self.composingText.insertAtCursorPosition(text, inputStyle: inputStyle)
        debug("Input Manager input:", composingText)
        if requireSetResult {
            // 変換を実施する
            self.setResult()
        }
    }

    @MainActor private func latinSmartPunctuationFieldIsAllowed() -> Bool {
        guard case .main = self.activeTextDocumentProxyPreference,
              let proxy = self.mainTextDocumentProxy else {
            return false
        }
        return !KeyboardViewController.isSecureField(proxy)
            && ItalianAutoAccentPolicy.allowsKeyboardType(proxy.keyboardType ?? .default)
            && ItalianAutoAccentPolicy.allowsTextContentType(proxy.textContentType)
    }

    @MainActor private func replaceSecondLatinSpaceWithPeriodIfNeeded(
        at uptime: TimeInterval,
        isLatinQwertyTab: Bool
    ) -> Bool {
        let elapsed = self.lastLatinSpaceTap.map { uptime - $0.uptime }
        let context = self.displayedTextManager.documentContextBeforeInput()
        guard self.composingText.isEmpty,
              !self.isSelected,
              (self.displayedTextManager.selectedText ?? "").isEmpty,
              DoubleSpacePeriodDecision.shouldReplace(
                  documentContextBeforeInput: context,
                  elapsedSincePreviousSpace: elapsed,
                  isEnabled: EnableDoubleSpacePeriod.value,
                  isLatinQwertyTab: isLatinQwertyTab,
                  languageUsesLatinScript: self.keyboardLanguage.usesLatinScript,
                  fieldAllowsReplacement: self.latinSmartPunctuationFieldIsAllowed()
              ),
              let context,
              let previousTap = self.lastLatinSpaceTap,
              previousTap.documentIdentifier == self.mainTextDocumentProxy?.documentIdentifier,
              context == previousTap.leftContext,
              (self.displayedTextManager.documentContextAfterInput ?? "") == previousTap.rightContext else {
            return false
        }

        self.clearLastLatinAutocorrection()
        self.clearLastLatinSpaceTap()
        let rightContext = self.displayedTextManager.documentContextAfterInput ?? ""
        let expectedLeftContext = String(context.dropLast()) + ". "
        self.displayedTextManager.deleteBackward(count: 1)
        self.displayedTextManager.insertText(". ")
        let observedLeftContext = self.displayedTextManager.documentContextBeforeInput()
        let observedRightContext = self.displayedTextManager.documentContextAfterInput ?? ""
        // Hosts expose a BOUNDED context window: after an edit the observed prefix may be
        // truncated, so snapshots are compared as tails, never as full equality alone
        // (counter-review major, 30/08). / ホストの文脈窓は有限：末尾一致で比較する。
        func tailMatches(_ observed: String?, _ expected: String) -> Bool {
            guard let observed else { return false }
            if observed == expected { return true }
            // Below three characters the outcomes stop being distinguishable — fail closed.
            // 3文字未満の窓では結果を判別できないため不一致として扱う。
            guard observed.count >= 3 else { return false }
            return expected.hasSuffix(observed) || observed.hasSuffix(expected)
        }
        if tailMatches(observedLeftContext, expectedLeftContext),
           observedLeftContext?.hasSuffix(". ") == true,
           observedRightContext == rightContext {
            self.lastDoubleSpacePeriod = LastDoubleSpacePeriod(
                documentIdentifier: previousTap.documentIdentifier,
                leftContextAfterReplacement: observedLeftContext ?? expectedLeftContext,
                rightContextAfterReplacement: rightContext
            )
        } else if tailMatches(observedLeftContext, context + ". "),
                  observedRightContext == rightContext {
            // The deletion was refused but the insertion went through ("ciao " -> "ciao . "):
            // converge back to the user's plain two spaces (counter-review blocker, 30/08).
            // 削除が拒否され挿入だけ通った場合：素の空白2つへ収束させる。
            self.displayedTextManager.deleteBackward(count: 2)
            self.displayedTextManager.insertText(" ")
        } else if tailMatches(observedLeftContext, context),
                  observedRightContext == rightContext {
            // The host rejected the whole replacement: fall through so the ordinary second space
            // is inserted. / 置換全体が拒否された場合は通常の2つ目の空白入力へ戻す。
            self.resetPostCompositionPredictionCandidates()
            return false
        } else if tailMatches(observedLeftContext, String(context.dropLast())),
                  observedRightContext == rightContext {
            // Only deletion was accepted: restore the user's two spaces without smart punctuation.
            // 削除だけ反映された場合は、スマート句読点を使わず空白2つへ復元する。
            self.displayedTextManager.insertText("  ")
        }
        // Any other observed state is unknown host behaviour: leave the text as the host settled
        // it and create no undo token — never guess further edits. / 未知の状態では追加編集しない。
        self.resetPostCompositionPredictionCandidates()
        return true
    }

    @MainActor private func rememberLatinSpaceTapIfEligible(
        text: String,
        at uptime: TimeInterval,
        isLatinQwertyTab: Bool
    ) {
        guard text == " ",
              EnableDoubleSpacePeriod.value,
              isLatinQwertyTab,
              self.keyboardLanguage.usesLatinScript,
              self.latinSmartPunctuationFieldIsAllowed() else {
            self.lastLatinSpaceTap = nil
            return
        }
        guard case .main = self.activeTextDocumentProxyPreference,
              let documentIdentifier = self.mainTextDocumentProxy?.documentIdentifier,
              let leftContext = self.displayedTextManager.documentContextBeforeInput() else {
            self.lastLatinSpaceTap = nil
            return
        }
        self.lastLatinSpaceTap = LastLatinSpaceTap(
            documentIdentifier: documentIdentifier,
            uptime: uptime,
            leftContext: leftContext,
            rightContext: self.displayedTextManager.documentContextAfterInput ?? ""
        )
    }

    private func shouldDirectInsert(text: String, simpleInsert: Bool) -> Bool {
        simpleInsert
            || text == "\n"
            || text == " " || text == "　" || text == "\t" || text == "\0"
            || self.keyboardLanguage == .none
    }

    @MainActor private func latinCorrectionForSpace() -> LatinSpaceCorrection? {
        let generalEnabled = EnableLatinAutocorrect.value
        let accentEnabled = self.keyboardLanguage == .it_IT && ItalianAutoAccentOnSpace.value
        let language: LatinAutocorrectPolicy.Language
        switch self.keyboardLanguage {
        case .it_IT:
            language = .italian
        case .en_US:
            language = .english
        default:
            return nil
        }

        guard generalEnabled || accentEnabled,
              !self.isSelected,
              !self.composingText.isEmpty,
              self.composingText.isAtEndIndex,
              let proxy = self.mainTextDocumentProxy,
              proxy.autocorrectionType != .no,
              !KeyboardViewController.isSecureField(proxy),
              ItalianAutoAccentPolicy.allowsKeyboardType(proxy.keyboardType ?? .default),
              ItalianAutoAccentPolicy.allowsTextContentType(proxy.textContentType) else {
            return nil
        }

        let typed = self.composingText.prefixToCursorPosition().convertTarget
        let context = proxy.documentContextBeforeInput.map { context in
            context.hasSuffix(typed) ? String(context.dropLast(typed.count)) : context
        }
        guard ItalianAutoAccentPolicy.allowsCapitalization(
            of: typed,
            documentContextBeforeInput: context
        ) else {
            return nil
        }

        var italianAutoAccentCandidateExists = false
        var preferredItalianAutoAccentCorrection: String?
        if language == .italian,
           let fix = ItalianAccentAutocorrect.accentFix(forTypedWord: typed) {
            italianAutoAccentCandidateExists = true
            // Copaky: A-01c keeps its own setting and double fail-closed oracle. When B-04 is also
            // on, this confirmed answer is passed into the general policy and wins without a second
            // spell-check query. If A-01c owns but rejects the word, the general path cannot claim it.
            // Copaky: A-01c の確認済み回答を優先し、同じ語を一般補正で再判定しない。
            if accentEnabled,
               ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: typed, fix: fix) {
                preferredItalianAutoAccentCorrection = fix
            }
        }

        // B-04 OFF preserves A-01c byte-for-byte at the behavior boundary, including no new undo.
        if !generalEnabled {
            return preferredItalianAutoAccentCorrection.map {
                LatinSpaceCorrection(original: typed, corrected: $0, undoEligible: false)
            }
        }

        let policyContext = LatinAutocorrectPolicy.Context(
            isEnabled: generalEnabled,
            keyboardType: proxy.keyboardType ?? .default,
            textContentType: proxy.textContentType,
            autocorrectionType: proxy.autocorrectionType,
            isSecureField: KeyboardViewController.isSecureField(proxy),
            documentContextBeforeWord: context,
            preferredItalianAutoAccentCorrection: preferredItalianAutoAccentCorrection,
            italianAutoAccentCandidateExists: italianAutoAccentCandidateExists
        )
        let evaluation = LatinAutocorrectPolicy.evaluate(
            forTypedWord: typed,
            language: language,
            context: policyContext
        )
#if DEBUG
        let spellCheck = evaluation.spellCheckResult
        let learned = spellCheck?.learnedGuesses ?? []
        let guessDiagnostics = spellCheck?.guesses.map { guess in
            "\(guess)[learned=\(learned.contains(guess))]"
        }.joined(separator: ",") ?? ""
        os_log(
            "typed=%{public}@ language=%{public}@ isMisspelled=%{public}@ guesses=%{public}d learnedByGuess=%{public}@ candidate=%{public}@ result=%{public}@",
            log: Self.autocorrectLog,
            type: .debug,
            typed,
            language.rawValue,
            spellCheck.map { String($0.isMisspelled) } ?? "unavailable",
            spellCheck?.guesses.count ?? 0,
            guessDiagnostics,
            evaluation.correction ?? evaluation.selectedCandidate ?? "none",
            evaluation.rejectionReason?.rawValue ?? "accepted"
        )
#endif
        guard let correction = evaluation.correction else {
            return nil
        }
        return LatinSpaceCorrection(original: typed, corrected: correction, undoEligible: true)
    }

    @MainActor func clearLastLatinAutocorrection() {
        self.lastLatinAutocorrection = nil
        self.lastDoubleSpacePeriod = nil
    }

    @MainActor func clearLastLatinSpaceTap() {
        self.lastLatinSpaceTap = nil
    }

    /// Keeps the one-shot undo across host no-op callbacks, while still invalidating it when the
    /// text, selection, or cursor context actually changed outside the keyboard action pipeline.
    /// ホストの無変更通知では復元状態を保持し、本文・選択・カーソルの実変更時だけ破棄する。
    @MainActor func clearLastLatinAutocorrectionIfContextChanged(
        left: String,
        center: String,
        right: String
    ) {
        if let correction = self.lastLatinAutocorrection,
           left != correction.leftContextAfterCorrection
               || !center.isEmpty
               || right != correction.rightContextAfterCorrection {
            self.lastLatinAutocorrection = nil
        }
        if let replacement = self.lastDoubleSpacePeriod,
           left != replacement.leftContextAfterReplacement
               || !center.isEmpty
               || right != replacement.rightContextAfterReplacement {
            self.lastDoubleSpacePeriod = nil
        }
        if let tap = self.lastLatinSpaceTap,
           left != tap.leftContext || !center.isEmpty || right != tap.rightContext {
            self.lastLatinSpaceTap = nil
        }
    }

    @MainActor private func rememberLatinAutocorrection(_ correction: LatinSpaceCorrection) {
        guard self.composingText.isEmpty,
              !self.isSelected,
              case .main = self.activeTextDocumentProxyPreference,
              let documentIdentifier = self.mainTextDocumentProxy?.documentIdentifier,
              let leftContext = self.displayedTextManager.documentContextBeforeInput(),
              leftContext.hasSuffix(correction.corrected + " ") else {
            return
        }
        self.lastLatinAutocorrection = LastLatinAutocorrection(
            documentIdentifier: documentIdentifier,
            original: correction.original,
            corrected: correction.corrected,
            leftContextAfterCorrection: leftContext,
            rightContextAfterCorrection: self.displayedTextManager.documentContextAfterInput ?? ""
        )
    }

    /// Restores the original word and consumes the just-inserted space. The exact surrounding-text
    /// snapshot makes this fail closed if the host moved the cursor or edited behind our back.
    @MainActor func undoLastLatinAutocorrectionIfPossible() -> Bool {
        guard let correction = self.lastLatinAutocorrection else {
            return false
        }
        self.lastLatinAutocorrection = nil
        // Counter-review blocker (30/08): without the document identity, a focus change onto a
        // second field with an identical context window could let Backspace rewrite the new field.
        // 文書IDなしでは、同一文脈の別フィールドへ移った後にBackspaceが誤って書き換え得る。
        guard self.composingText.isEmpty,
              !self.isSelected,
              case .main = self.activeTextDocumentProxyPreference,
              correction.documentIdentifier == self.mainTextDocumentProxy?.documentIdentifier,
              (self.displayedTextManager.selectedText ?? "").isEmpty,
              self.displayedTextManager.documentContextBeforeInput() == correction.leftContextAfterCorrection,
              (self.displayedTextManager.documentContextAfterInput ?? "") == correction.rightContextAfterCorrection,
              correction.leftContextAfterCorrection.hasSuffix(correction.corrected + " ") else {
            return false
        }

        self.displayedTextManager.deleteBackward(count: correction.corrected.count + 1)
        self.displayedTextManager.insertText(correction.original)
        self.resetPostCompositionPredictionCandidates()
        return true
    }

    /// Restores the two literal spaces and consumes the one-shot token. Exact context matching keeps
    /// host edits and cursor moves fail-closed. / 2つの空白を戻し、文脈不一致時は何もしない。
    @MainActor func undoLastDoubleSpacePeriodIfPossible() -> Bool {
        guard let replacement = self.lastDoubleSpacePeriod else {
            return false
        }
        self.lastDoubleSpacePeriod = nil
        guard self.composingText.isEmpty,
              !self.isSelected,
              case .main = self.activeTextDocumentProxyPreference,
              replacement.documentIdentifier == self.mainTextDocumentProxy?.documentIdentifier,
              (self.displayedTextManager.selectedText ?? "").isEmpty,
              self.displayedTextManager.documentContextBeforeInput() == replacement.leftContextAfterReplacement,
              (self.displayedTextManager.documentContextAfterInput ?? "") == replacement.rightContextAfterReplacement,
              replacement.leftContextAfterReplacement.hasSuffix(". ") else {
            return false
        }

        self.displayedTextManager.deleteBackward(count: 2)
        self.displayedTextManager.insertText("  ")
        self.resetPostCompositionPredictionCandidates()
        return true
    }

    /// テキストの進行方向に削除する
    /// `ab|c → ab|`のイメージ
    @MainActor func deleteForward(count: Int, requireSetResult: Bool = true) {
        if count < 0 {
            return
        }

        guard !self.composingText.isEmpty else {
            self.displayedTextManager.deleteForward(count: count)
            return
        }

        self.composingText.deleteForwardFromCursorPosition(count: count)
        debug("Input Manager deleteForward: ", composingText)

        if requireSetResult {
            // 変換を実施する
            self.setResult()
        }
    }

    /// テキストの進行方向と逆に削除する
    /// `ab|c → a|c`のイメージ
    /// - Parameters:
    ///   - convertTargetCount: `convertTarget`の文字数。`displayedText`の文字数ではない。
    ///   - requireSetResult: `setResult()`の呼び出しを要求するか。
    @MainActor func deleteBackward(convertTargetCount: Int, requireSetResult: Bool = true) {
        if convertTargetCount == 0 {
            return
        }
        // 選択状態ではオール削除になる
        if self.isSelected {
            // 選択部分を削除する
            self.displayedTextManager.deleteBackward(count: 1)
            // 変換をリセットする
            self.stopComposition()
            return
        }
        // 条件
        if convertTargetCount < 0 {
            self.deleteForward(count: abs(convertTargetCount), requireSetResult: requireSetResult)
            return
        }
        guard !self.composingText.isEmpty else {
            self.displayedTextManager.deleteBackward(count: convertTargetCount)
            return
        }

        self.composingText.deleteBackwardFromCursorPosition(count: convertTargetCount)
        debug("Input Manager deleteBackword: ", composingText)

        if requireSetResult {
            // 変換を実施する
            self.setResult()
        }
    }

    /// 特定の文字まで削除する
    ///  - returns: 削除した文字列
    @MainActor func smoothDelete(to nexts: [Character] = ["、", "。", "！", "？", ".", ",", "．", "，", "\n"], requireSetResult: Bool = true) -> String {
        // 選択状態ではオール削除になる
        if self.isSelected {
            let targetText = self.composingText.convertTarget
            // 選択部分を完全に削除する
            self.displayedTextManager.deleteBackward(count: 1)
            // Compositionをリセットする
            self.stopComposition()
            return targetText
        }
        // 入力中の場合
        if !self.composingText.isEmpty {
            // この実装は、ライブ変換時はカーソルより右に文字列が存在しないことが保証されているために有効になっている。
            let targetText = self.displayedTextManager.displayedLiveConversionText ?? String(self.composingText.convertTargetBeforeCursor)
            // カーソルより前を全部消す
            self.composingText.deleteBackwardFromCursorPosition(count: self.composingText.convertTargetCursorPosition)
            // 文字がもうなかった場合、ここで全て削除して終了
            if self.composingText.isEmpty {
                // 全て削除する
                self.displayedTextManager.updateComposingText(composingText: self.composingText, newLiveConversionText: nil)
                self.stopComposition()
                return targetText
            }
            // カーソルを先頭に移動する
            self.moveCursor(count: self.composingText.convertTarget.count)
            if requireSetResult {
                setResult()
            }
            return targetText
        }

        var deletedCount = 0
        var targetText = ""
        while let last = self.displayedTextManager.documentContextBeforeInput()?.last {
            if nexts.contains(last) {
                break
            } else {
                targetText.insert(last, at: targetText.startIndex)
                self.displayedTextManager.deleteBackward(count: 1)
                deletedCount += 1
            }
        }
        if deletedCount == 0 {
            if let last = self.displayedTextManager.documentContextBeforeInput()?.last {
                targetText.insert(last, at: targetText.startIndex)
            }
            self.displayedTextManager.deleteBackward(count: 1)
        }
        return targetText
    }

    /// テキストの進行方向に、特定の文字まで削除する
    /// 入力中はカーソルから右側を全部消す
    @MainActor func smoothDeleteForward(to nexts: [Character] = ["、", "。", "！", "？", ".", ",", "．", "，", "\n"], requireSetResult: Bool = true) -> String {
        // 選択状態ではオール削除になる
        if self.isSelected {
            let targetText = self.composingText.convertTarget
            // 完全に削除する
            self.displayedTextManager.deleteBackward(count: 1)
            // Compositionをリセットする
            self.stopComposition()
            return targetText
        }
        // 入力中の場合
        if !self.composingText.isEmpty {
            // TODO: Check implementation of `requireSetResult`
            // count文字消せるのは自明なので、返り値は無視できる
            let targetText = self.composingText.convertTarget.suffix(self.composingText.convertTarget.count - self.composingText.convertTargetCursorPosition)
            self.composingText.deleteForwardFromCursorPosition(count: self.composingText.convertTarget.count - self.composingText.convertTargetCursorPosition)
            // 文字がもうなかった場合
            if self.composingText.isEmpty {
                // 全て削除する
                self.displayedTextManager.updateComposingText(composingText: self.composingText, newLiveConversionText: nil)
                self.stopComposition()
            }
            // setResultを呼ばない(カーソル右側の文字列は変換対象にならないため)
            return String(targetText)
        }

        var deletedCount = 0
        var targetText = ""
        while let first = self.displayedTextManager.documentContextAfterInput?.first {
            if nexts.contains(first) {
                break
            } else {
                self.displayedTextManager.deleteForward(count: 1)
                targetText.append(first)
                deletedCount += 1
            }
        }
        if deletedCount == 0 {
            if let first = self.displayedTextManager.documentContextAfterInput?.first {
                targetText.append(first)
            }
            self.displayedTextManager.deleteForward(count: 1)
        }
        return targetText
    }

    /// テキストの進行方向と逆に、特定の文字までカーソルを動かす
    @MainActor func smartMoveCursorBackward(to nexts: [Character] = ["、", "。", "！", "？", ".", ",", "．", "，", "\n"], requireSetResult: Bool = true) {
        // 選択状態では左にカーソルを移動
        if isSelected {
            // 左にカーソルを動かす
            self.displayedTextManager.moveCursor(count: -1)
            self.stopComposition()
            return
        }
        // 入力中の場合
        if !composingText.isEmpty {
            if self.liveConversionEnabled {
                _ = self.enter()
                return
            }
            _ = self.composingText.moveCursorFromCursorPosition(count: -self.composingText.convertTargetCursorPosition)
            if requireSetResult {
                self.setResult()
            }
            return
        }

        var movedCount = 0
        while let last = displayedTextManager.documentContextBeforeInput()?.last {
            if nexts.contains(last) {
                break
            } else {
                self.displayedTextManager.moveCursor(count: -1)
                movedCount += 1
            }
        }
        if movedCount == 0 {
            self.displayedTextManager.moveCursor(count: -1)
        }
    }

    /// テキストの進行方向に、特定の文字までカーソルを動かす
    @MainActor func smartMoveCursorForward(to nexts: [Character] = ["、", "。", "！", "？", ".", ",", "．", "，", "\n"], requireSetResult: Bool = true) {
        // 選択状態では最も右にカーソルを移動
        if isSelected {
            self.displayedTextManager.moveCursor(count: 1)
            self.stopComposition()
            return
        }
        // 入力中の場合
        if !composingText.isEmpty {
            if self.liveConversionEnabled {
                _ = self.enter()
                return
            }
            _ = self.composingText.moveCursorFromCursorPosition(count: self.composingText.convertTarget.count - self.composingText.convertTargetCursorPosition)
            if requireSetResult {
                setResult()
            }
            return
        }

        var movedCount = 0
        while let first = displayedTextManager.documentContextAfterInput?.first {
            if nexts.contains(first) {
                break
            } else {
                self.displayedTextManager.moveCursor(count: 1)
                movedCount += 1
            }
        }
        if movedCount == 0 {
            self.displayedTextManager.moveCursor(count: 1)
        }
    }

    /// iOS16以上の仕様変更に対応するため追加されたAPI
    func adjustLeftString(_ left: String) -> String {
        var newLeft = left.components(separatedBy: "\n").last ?? ""
        if left.contains("\n") && newLeft.isEmpty {
            newLeft = "\n"
        }
        return newLeft
    }

    /// クリップボードの文字列をペーストする
    @MainActor func paste() {
        guard let text = UIPasteboard.general.string else {
            return
        }
        guard !text.isEmpty else {
            return
        }
        if isSelected {
            // 選択部分を削除する
            self.deleteSelection()
        }
        self.input(text: text, simpleInsert: true, inputStyle: .direct)
    }

    /// 文字のreplaceを実施する
    /// `changeCharacter`を`CustardKit`で扱うためのAPI。
    /// キーボード経由でのみ実行される。
    @MainActor func replaceLastCharacters(table: [String: String], requireSetResult: Bool = true, inputStyle: InputStyle) {
        debug(table, composingText, isSelected)
        if isSelected {
            if let replace = table[self.composingText.convertTarget] {
                // 選択部分を削除する
                self.deleteSelection()
                // 入力を実行する
                self.input(text: replace, simpleInsert: true, inputStyle: .direct)
            }
            return
        }
        let counts: (max: Int, min: Int) = table.keys.reduce(into: (max: 0, min: .max)) {
            $0.max = max($0.max, $1.count)
            $0.min = min($0.min, $1.count)
        }
        // 入力状態の場合、入力中のテキストの範囲でreplaceを実施する。
        if !composingText.isEmpty {
            let leftside = composingText.convertTargetBeforeCursor
            var found = false
            for count in (counts.min...counts.max).reversed() where count <= composingText.convertTargetCursorPosition {
                if let replace = table[String(leftside.suffix(count))] {
                    // deleteとinputを効率的に行うため、setResultを要求しない (変換を行わない)
                    self.deleteBackward(convertTargetCount: leftside.suffix(count).count, requireSetResult: false)
                    // ここで変換が行われる。内部的には差分管理システムによって「置換」の場合のキャッシュ変換が呼ばれる。
                    self.input(text: replace, requireSetResult: requireSetResult, inputStyle: inputStyle)
                    found = true
                    break
                }
            }
            if !found && requireSetResult {
                self.setResult()
            }
            return
        }
        // 言語の指定がない場合は、入力中のテキストの範囲でreplaceを実施する。
        if keyboardLanguage == .none {
            let leftside = displayedTextManager.documentContextBeforeInput() ?? ""
            for count in (counts.min...counts.max).reversed() where count <= leftside.count {
                if let replace = table[String(leftside.suffix(count))] {
                    self.displayedTextManager.deleteBackward(count: count)
                    self.displayedTextManager.insertText(replace)
                    break
                }
            }
        }
    }

    /// カーソル左側の1文字を変更する関数
    /// ひらがなの場合は小書き・濁点・半濁点化し、英字・ギリシャ文字・キリル文字の場合は大文字・小文字化する
    @MainActor func changeCharacter(behavior: ReplaceBehavior, requireSetResult: Bool = true, inputStyle: InputStyle) {
        if self.isSelected {
            return
        }
        guard let char = self.composingText.convertTargetBeforeCursor.last else {
            return
        }
        let changed = ReplaceBehaviorManager.apply(replaceBehavior: behavior, to: char)
        // 同じ文字の場合は無視する
        if Character(changed) == char {
            return
        }
        // deleteとinputを効率的に行うため、setResultを要求しない (変換を行わない)
        self.deleteBackward(convertTargetCount: 1, requireSetResult: false)
        // inputの内部でsetResultが発生する
        self.input(text: changed, requireSetResult: requireSetResult, inputStyle: inputStyle)
    }

    /// キーボード経由でのカーソル移動
    @MainActor func moveCursor(count: Int, requireSetResult: Bool = true) {
        self.clearLastLatinAutocorrection()
        if self.isSelected {
            // ただ横に動かす(選択解除)
            self.displayedTextManager.moveCursor(count: 1)
            // 解除する
            self.stopComposition()
            return
        }
        if count == 0 {
            return
        }
        // 入力中の文字が空の場合は普通に動かす
        if composingText.isEmpty {
            self.displayedTextManager.moveCursor(count: count)
            return
        }
        if self.liveConversionEnabled {
            _ = self.enter()
            return
        }

        debug("Input Manager moveCursor:", composingText, count)

        _ = self.composingText.moveCursorFromCursorPosition(count: count)
        if count != 0 && requireSetResult {
            setResult()
        }
    }

    /// ユーザがキーボードを経由せずにカーソルを何かした場合の後処理を行う関数。
    ///  - note: この関数をユーティリティとして用いてはいけない。
    @MainActor func userMovedCursor(count: Int) -> [ActionType] {
        self.clearLastLatinAutocorrection()
        debug("userによるカーソル移動を検知、今の位置は\(composingText.convertTargetCursorPosition)、動かしたオフセットは\(count)")
        // 選択しているテキストがある場合はリザルトバーを表示する
        if self.isSelected {
            // リザルトバーを表示する
            return [.setCursorBar(.off), .setTabBar(.off)]
        }
        @KeyboardSetting(.displayCursorBarAutomatically) var displayCursorBarAutomatically
        // 入力テキストなし
        if self.composingText.isEmpty {
            return displayCursorBarAutomatically ? [.setCursorBar(.on)] : []
        }
        // ライブ変換有効
        if liveConversionEnabled {
            return displayCursorBarAutomatically ? [.setCursorBar(.on)] : []
        }
        let actualCount = composingText.moveCursorFromCursorPosition(count: count)
        _ = self.displayedTextManager.updateComposingText(composingText: self.composingText, userMovedCount: count, adjustedMovedCount: actualCount)
        setResult()
        return [.setCursorBar(.off), .setTabBar(.off)]
    }

    /// ユーザが行を跨いでカーソルを動かした場合に利用する
    @MainActor func userJumpedCursor() -> [ActionType] {
        self.clearLastLatinAutocorrection()
        if self.composingText.isEmpty {
            @KeyboardSetting(.displayCursorBarAutomatically) var displayCursorBarAutomatically
            return displayCursorBarAutomatically ? [.setCursorBar(.on)] : []
        }
        self.stopComposition()
        return []
    }

    /// ユーザがキーボードを経由せずカットした場合の処理
    @MainActor func userCutText(text: String) {
        self.stopComposition()
    }

    @MainActor func forgetMemory(_ candidate: Candidate) {
        self.kanaKanjiConverter.forgetMemory(candidate)
    }

    @MainActor func importDynamicUserDictionary(_ userDictionary: [DicdataElement]) {
        self.kanaKanjiConverter.importDynamicUserDictionary(userDictionary)
    }

    // Reference: https://teratail.com/questions/57039?link=qa_related_pc
    func getReadingFromSystemAPI(_ text: String) -> String {
        let inputText = text as NSString
        let outputText = NSMutableString()

        // トークナイザ
        let tokenizer: CFStringTokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            inputText as CFString,
            CFRangeMake(0, inputText.length),
            kCFStringTokenizerUnitWordBoundary,
            CFLocaleCopyCurrent()
        )

        // 形態素解析した結果を順に得る
        var tokenType: CFStringTokenizerTokenType = CFStringTokenizerGoToTokenAtIndex(tokenizer, 0)
        while tokenType.rawValue != 0 {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let original = inputText.substring(with: NSRange(location: range.location, length: range.length))
            if original.isEnglishSentence {
                outputText.append(original)
            } else if let romaji = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? NSString {
                // ローマ字をまず得て、そのあとでカタカナにする
                // Copaky: `mutableCopy()` of an NSString always yields NSMutableString; the optional
                // cast only removes a force-cast on a path fed by host-app text. / 強制キャストを避ける。
                let reading = NSMutableString(string: romaji as String)
                CFStringTransform(reading as CFMutableString, nil, kCFStringTransformLatinKatakana, false)
                outputText.append(reading as String)
            } else {
                // タイ語の文字など扱えない文字が入ってくるとここに来うる
                outputText.append(original)
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        return (outputText as String).toHiragana()
    }

    // ユーザが文章を選択した場合、その部分を入力中であるとみなす(再変換)
    @MainActor func userSelectedText(text: String, lengthLimit: Int) {
        self.composingText.stopComposition()
        // 文字がない場合
        if text.isEmpty
            // 文字数が多すぎる場合
            || text.count > lengthLimit
            // httpで始まる場合
            || text.hasPrefix("http")
            // 扱いにくい文字を含む場合
            || text.contains("\n") || text.contains("\r") || text.contains(" ") || text.contains("\t") {
            self.setResult()
            return
        }
        // 過去のログを見て、再変換に利用する
        let ruby = getReadingFromSystemAPI(self.getRubyIfPossible(text: text) ?? text)
        self.composingText.insertAtCursorPosition(ruby, inputStyle: .direct)

        self.isSelected = true
        self.setResult()
    }

    /// 選択を解除した場合、Compositionをリセットする
    @MainActor func userDeselectedText() {
        self.stopComposition()
    }

    /// 変換リクエストを送信し、結果をDisplayed Textにも反映する関数
    @MainActor func setResult() {
        let inputData = composingText.prefixToCursorPosition()
        debug("InputManager.setResult: value to be input", inputData)
        let options = self.getConvertRequestOptions(inputStylePreference: inputData.input.last?.inputStyle)
        debug("InputManager.setResult: options", options)
        let results = self.kanaKanjiConverter.requestCandidates(inputData, options: options)

        // 表示を更新する
        if !self.isSelected {
            if liveConversionEnabled {
                let liveConversionText = self.liveConversionManager.updateWithNewResults(inputData, results.mainResults, firstClauseResults: results.firstClauseResults, convertTargetCursorPosition: inputData.convertTargetCursorPosition, convertTarget: inputData.convertTarget)
                self.displayedTextManager.updateComposingText(composingText: self.composingText, newLiveConversionText: liveConversionText)
            } else {
                self.displayedTextManager.updateComposingText(composingText: self.composingText, newLiveConversionText: nil)
            }
        }

        if let updateResult {
            updateResult { model in
                model.setResults(results.mainResults)
                model.resetSupplementaryCandidates()
            }
            if inputData.convertTarget == "えもじ", #available(iOS 26, *) {
                self.triggerFoundationModelEmojiSuggestion(for: inputData)
            }
            if liveConversionEnabled, let firstClause = self.liveConversionManager.candidateForCompleteFirstClause() {
                debug("InputManager.setResult: Complete first clause", firstClause)
                self.complete(candidate: firstClause)
            }
        }
    }
}

struct EmojiTabShortcutCandidate: ResultViewItemData {
    let systemImageName: String
    let accessibilityLabel: String
    var inputable: Bool { true }
    var label: ResultViewItemLabelStyle { .systemImage(name: systemImageName, accessibilityLabel: accessibilityLabel) }
    #if DEBUG
    func getDebugInformation() -> String { "EmojiTabShortcutCandidate" }
    #endif
    init(systemImageName: String = "ellipsis.circle", accessibilityLabel: String = String(localized: "絵文字キーボードを開く")) {
        self.systemImageName = systemImageName
        self.accessibilityLabel = accessibilityLabel
    }
}

@available(iOS 26, *)
private extension InputManager {
    func rendersAsSingleGlyph(_ s: String, font: UIFont = .systemFont(ofSize: 17)) -> Bool {
        let attr = NSAttributedString(string: s, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr as CFAttributedString)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        var glyphCount = 0
        for run in runs {
            glyphCount += CTRunGetGlyphCount(run)
        }
        return glyphCount == 1
    }

    @Generable
    struct EmojiSuggestion {
        @Guide(description: "Emoji Suggestions for the given context. Give 1-5 suggestions. Each suggestion must be a single character.")
        var emojis: [String]
    }

    @MainActor
    private func triggerFoundationModelEmojiSuggestion(for inputData: ComposingText) {
        let leftContext = self.getSurroundingText().leftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextSnippet = String(leftContext.suffix(120))
        @KeyboardSetting(.additionalSystemDictionarySetting) var additionalSystemDictionarySetting
        let emojiDenylist = additionalSystemDictionarySetting.systemDictionarySettings[.emoji]?.denylist ?? []
        Task { [weak self] in
            guard let self else { return }
            let model = SystemLanguageModel(useCase: .general)
            guard model.isAvailable else {
                debug("Model is not available in this context.", model.availability)
                return
            }
            let session = LanguageModelSession(
                model: model,
                instructions: "You are an emoji recommendation engine. Read the provided CONTEXT and suggest 1-5 emojis that best match the overall meaning, tone, or sentiment. Reply with only emoji characters separated by spaces."
            )
            guard !contextSnippet.isEmpty else {
                debug("FoundationModels skipped", "empty context")
                return
            }
            let finalPrompt = "context: \(contextSnippet)"
            let response = session.streamResponse(to: finalPrompt, generating: EmojiSuggestion.self)
            do {
                for try await partiallyGenerated in response {
                    debug("FoundationModels partial", partiallyGenerated)
                }
                let collected = try await response.collect()
                let filteredEmojis: [String] = collected.content.emojis
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { emoji in
                        if emoji.count != 1 {
                            return false
                        }
                        if emojiDenylist.contains(emoji) {
                            return false
                        }
                        if emoji.unicodeScalars.contains(where: { scalar in
                            emojiDenylist.contains(String(scalar))
                        }) {
                            return false
                        }
                        if !self.rendersAsSingleGlyph(emoji) {
                            return false
                        }
                        return true
                    }
                guard !filteredEmojis.isEmpty else { return }
                var candidates: [any ResultViewItemData] = filteredEmojis.uniqued().prefix(5).map { Self.makeEmojiCandidate(from: $0, composingCount: .surfaceCount(inputData.convertTargetCursorPosition)) }
                let shortcut = EmojiTabShortcutCandidate()
                candidates.append(shortcut)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.composingText.convertTarget == inputData.convertTarget,
                          self.composingText.convertTargetCursorPosition == inputData.convertTargetCursorPosition else {
                        debug("FoundationModels skipped", "stale context")
                        return
                    }
                    self.updateResult? { model in
                        model.setSupplementaryCandidates(candidates)
                    }
                }
            } catch {
                debug("FoundationModels error", error)
            }
        }
    }

    private static func makeEmojiCandidate(from text: String, composingCount: ComposingCount) -> Candidate {
        Candidate(
            text: text,
            value: -1,
            composingCount: composingCount,
            lastMid: MIDData.一般.mid,
            data: [
                DicdataElement(
                    word: text,
                    ruby: "えもじ",
                    cid: CIDData.記号.cid,
                    mid: MIDData.一般.mid,
                    value: -1
                ),
            ],
            actions: [],
            inputable: true,
            isLearningTarget: false
        )
    }
}

extension Candidate: @retroactive ResultViewItemData {
    public var label: ResultViewItemLabelStyle { .text(self.text) }
    #if DEBUG
    public func getDebugInformation() -> String {
        "Candidate(text: \(self.text), value: \(self.value), data: \(self.data.debugDescription))"
    }
    #endif
}

extension CompleteAction {
    var action: ActionType {
        switch self {
        case .moveCursor(let value):
            return .moveCursor(value)
        }
    }
}

extension ReplacementCandidate: @retroactive ResultViewItemData {
    public var label: ResultViewItemLabelStyle { .text(self.text) }
}

extension TextReplacer.SearchResultItem: @retroactive ResultViewItemData {
    public var label: ResultViewItemLabelStyle { .text(self.text) }
}

// TextReplacerがprintされると非常に長大なログが発生して支障があるため
extension TextReplacer: @retroactive CustomStringConvertible {
    public var description: String {
        "TextReplacer(emojiSearchDict: [...], emojiGroups: [...], nonBaseEmojis: [...])"
    }
}

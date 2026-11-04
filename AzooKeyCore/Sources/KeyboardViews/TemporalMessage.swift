//
//  TemporalMessage.swift
//
//
//  Created by ensan on 2023/07/22.
//

import Foundation
import struct SwiftUI.LocalizedStringKey

public enum TemporalMessage: Equatable, Sendable {
    // Copaky [H-17]: explicit acknowledgement keeps manual-opening instructions readable.
    case openCopakyManually
    case appLaunchUnavailable

    public static func blockedAppLaunch(scheme: String) -> Self {
        URL(string: scheme)?.scheme?.lowercased() == "copaky" ? .openCopakyManually : .appLaunchUnavailable
    }

    case doneForgetCandidate
    case clipboardCaptureTooLarge
    /// Copaky [G-38]
    case clipboardHistoryFull
    case clipboardHistoryUnavailable
    case clipboardHistorySaveFailed

    var title: LocalizedStringKey {
        switch self {
        case .openCopakyManually:
            return "設定を変更するには、ホーム画面からCopakyアプリを開き、「設定」タブを選んでください。"
        case .appLaunchUnavailable:
            return "キーボードからアプリやショートカットは起動できません。ホーム画面から目的のアプリを開いてください。"
        case .doneForgetCandidate:
            return "候補の学習をリセットしました"
        case .clipboardCaptureTooLarge:
            return "クリップボードが大きすぎるため追加できませんでした"
        case .clipboardHistoryFull:
            return "ピン留めが多すぎて履歴に追加できませんでした"
        case .clipboardHistoryUnavailable:
            return "クリップボード履歴を読み込めません。Copaky アプリを開いて修復してください"
        case .clipboardHistorySaveFailed:
            return "クリップボード履歴を保存できませんでした"
        }
    }

    public enum DismissCondition: Sendable {
        case auto
        case ok
    }

    var dismissCondition: DismissCondition {
        switch self {
        case .openCopakyManually, .appLaunchUnavailable: return .ok
        case .doneForgetCandidate: return .auto
        case .clipboardCaptureTooLarge, .clipboardHistoryFull, .clipboardHistoryUnavailable, .clipboardHistorySaveFailed: return .auto
        }
    }
}

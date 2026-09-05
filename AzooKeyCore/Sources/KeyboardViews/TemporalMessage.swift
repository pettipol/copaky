//
//  TemporalMessage.swift
//
//
//  Created by ensan on 2023/07/22.
//

import struct SwiftUI.LocalizedStringKey

public enum TemporalMessage: Sendable {
    case doneForgetCandidate
    case clipboardCaptureTooLarge
    /// Copaky [G-38]
    case clipboardHistoryFull
    case clipboardHistoryUnavailable
    case clipboardHistorySaveFailed

    var title: LocalizedStringKey {
        switch self {
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
        case .doneForgetCandidate: return .auto
        case .clipboardCaptureTooLarge, .clipboardHistoryFull, .clipboardHistoryUnavailable, .clipboardHistorySaveFailed: return .auto
        }
    }
}

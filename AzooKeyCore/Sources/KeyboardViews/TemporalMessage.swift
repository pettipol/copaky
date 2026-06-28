//
//  TemporalMessage.swift
//
//
//  Created by ensan on 2023/07/22.
//

import struct SwiftUI.LocalizedStringKey

public enum TemporalMessage: Sendable {
    case doneForgetCandidate

    var title: LocalizedStringKey {
        switch self {
        case .doneForgetCandidate:
            return "候補の学習をリセットしました"
        }
    }

    public enum DismissCondition: Sendable {
        case auto
        case ok
    }

    var dismissCondition: DismissCondition {
        switch self {
        case .doneForgetCandidate: return .auto
        }
    }
}

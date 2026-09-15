//
//  StrokeAndFill.swift
//  azooKey
//
//  Created by ensan on 2021/02/26.
//  Copyright © 2021 ensan. All rights reserved.
//

import Foundation
import SwiftUI

public extension Shape {
    // Copaky (Xcode 27, SDK iOS 27): the package targets iOS 17+, so the pre-iOS 17 ZStack fallback was dead
    // code and no longer compiles under the iOS 27 SDK; keep the iOS 17 fill-then-stroke path only.
    // Copaky（Xcode 27 / iOS 27 SDK）：パッケージはiOS 17以上が対象のため、iOS 17未満向けのZStackフォールバックは不要。
    func strokeAndFill(fillContent: some ShapeStyle, strokeContent: some ShapeStyle, lineWidth: CGFloat) -> some View {
        self
            .fill(fillContent)
            .stroke(strokeContent, lineWidth: lineWidth)
    }
}

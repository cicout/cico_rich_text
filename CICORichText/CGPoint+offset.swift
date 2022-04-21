//
//  CGPoint+offset.swift
//  CICORichText
//
//  Created by Ethan.Li on 2022/4/21.
//

import Foundation
import CoreGraphics

extension CGPoint {
    public func offset(dx offsetX: CGFloat, dy offsetY: CGFloat ) -> CGPoint {
        return CGPoint.init(x: self.x + offsetX, y: self.y + offsetY)
    }
}

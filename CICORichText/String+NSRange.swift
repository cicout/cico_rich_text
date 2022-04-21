//
//  String+NSRange.swift
//  CICORichText
//
//  Created by Ethan.Li on 2022/4/21.
//

import Foundation
import SwiftRichString

extension String {
    public func nsrange(fromRange range: Range<String.Index>) -> NSRange {
        return NSRange(range, in: self)
    }

    public func subString(in nsrange: NSRange) -> String? {
        guard let range = self.rangeFrom(nsRange: nsrange) else {
            return nil
        }
        return self[range].string
    }
}

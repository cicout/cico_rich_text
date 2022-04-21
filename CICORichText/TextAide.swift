//
//  TextAide.swift
//  CICORichText
//
//  Created by Ethan.Li on 2021/12/18.
//

import Foundation
import CoreText
import CoreGraphics
import SwiftRichString
import UIKit

public struct WrapInfo {
    public struct WrapString {
        var text: NSAttributedString
        var tapRange: NSRange?
    }

    public var unwrapString: WrapString
    public var wrapString: WrapString
}

public enum WrapStatus: Int {
    case normal
    case wrapped
    case unwrapped

    public func isNormal() -> Bool {
        return self == .normal
    }

    public func isWrapped() -> Bool {
        return self == .wrapped
    }

    public func isUnwrapped() -> Bool {
        return self == .unwrapped
    }
}

public struct HighlightType: OptionSet {
    public let rawValue: Int

    public static let atUser = HighlightType.init(rawValue: 1 << 0)
    public static let sharp = HighlightType.init(rawValue: 1 << 1)
    public static let link = HighlightType.init(rawValue: 1 << 2)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public func regexPattern(extraRegexPattern: String = "") -> String {
        var patterns = [String].init()

        if self.contains(.atUser) {
            patterns.append("[@][^@# \\n]+?(?=[ ]|$)")
        }

        if self.contains(.sharp) {
            patterns.append("[#][^@# \\n]+?(?=[ ])")
        }

        if self.contains(.link) {
            patterns.append("https?://[-A-Za-z0-9+&@#/%?=~_|!:,.;]+?(?=[ ]|$)")
        }

        if extraRegexPattern.count > 0 {
            patterns.append(extraRegexPattern)
        }

        return patterns.joined(separator: "|")
    }

    public func isNone() -> Bool {
        return self.isEmpty
    }

    public func hasSharp() -> Bool {
        return self.contains(.sharp)
    }

    public func hasAt() -> Bool {
        return self.contains(.atUser)
    }
}

public struct MatchString {
    public var text: String
    public var range: NSRange

    public init(text: String = "", range: NSRange = .init(location: 0, length: 0)) {
        self.text = text
        self.range = range
    }
}

public class TextAide {
    public static func truncate(attributedText: NSMutableAttributedString,
                                limitWidth: CGFloat,
                                limitLineCount: Int,
                                truncationString: NSAttributedString) -> Bool {
        guard limitLineCount > 0, limitWidth > 0 else {
            return false
        }

        let setter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let rect = CGRect.init(x: 0, y: 0, width: limitWidth, height: CGFloat.greatestFiniteMagnitude)
        let path = CGPath.init(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange.init(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame)
        var lineCount = CFArrayGetCount(lines)
        if attributedText.string.hasSuffix("\n") {
            lineCount += 1
        }

        guard lineCount > limitLineCount else {
            return false
        }

        let lastLine = unsafeBitCast(CFArrayGetValueAtIndex(lines, limitLineCount - 1), to: CTLine.self)
        let truncationWidth = self.textSize(attributedText: truncationString, limitWidth: limitWidth).width
        let position = CGPoint.init(x: limitWidth - truncationWidth - 10, y: 0)
        var lastCharLocation = CTLineGetStringIndexForPosition(lastLine, position)
        let lastCharRange = NSRange.init(location: lastCharLocation - 1, length: 1)
        if let lastChar = attributedText.string.subString(in: lastCharRange), lastChar == "\n" {
            lastCharLocation -= 1
        }

        let leftRange = NSRange.init(location: 0, length: lastCharLocation)
        let leftText = attributedText.attributedSubstring(from: leftRange)
        attributedText.deleteCharacters(in: NSRange.init(location: 0,
                                                         length: (attributedText.string as NSString).length))
        attributedText.append(leftText)
        attributedText.append(truncationString)

        return true
    }

    public static func lineCount(attributedText: NSAttributedString, limitWidth: CGFloat) -> Int {
        let setter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let rect = CGRect.init(x: 0, y: 0, width: limitWidth, height: CGFloat.greatestFiniteMagnitude)
        let path = CGPath.init(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange.init(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame)
        var lineCount = CFArrayGetCount(lines)
        if attributedText.string.hasSuffix("\n") {
            lineCount += 1
        }
        return lineCount
    }

    public static func textSize(attributedText: NSAttributedString,
                                limitWidth: CGFloat,
                                limitLineCount: Int = 0,
                                truncationString: NSAttributedString? = nil) -> CGSize {
        let size = CGSize.init(width: limitWidth, height: CGFloat.greatestFiniteMagnitude)

        guard limitLineCount > 0 else {
            let textSize = attributedText.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil).size
            return self.fixSize(size: textSize)
        }

        let fixedText = NSMutableAttributedString.init(attributedString: attributedText)

        let font = attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let style = Style.init {
            $0.font = font
        }
        let fixedTruncationString = truncationString ?? "... More".set(style: style)

        _ =
        self.truncate(attributedText: fixedText,
                      limitWidth: limitWidth,
                      limitLineCount: limitLineCount,
                      truncationString: fixedTruncationString)

        let textSize = fixedText.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil).size
        return self.fixSize(size: textSize)
    }

    public static func createAttributedString(text: String,
                                              font: UIFont,
                                              color: UIColor = .white,
                                              alignment: NSTextAlignment = .left,
                                              lineSpacing: CGFloat = 0) -> NSAttributedString {
        let style = Style.init {
            $0.font = font
            $0.color = color
            $0.alignment = alignment
            $0.lineSpacing = lineSpacing
        }
        return text.set(style: style)
    }

    public static func lineCount(text: String,
                                 font: UIFont,
                                 limitWidth: CGFloat,
                                 color: UIColor = .white,
                                 alignment: NSTextAlignment = .left,
                                 lineSpacing: CGFloat = 0) -> Int {
        let attributedText = self.createAttributedString(text: text,
                                                         font: font,
                                                         color: color,
                                                         alignment: alignment,
                                                         lineSpacing: lineSpacing)
        return self.lineCount(attributedText: attributedText, limitWidth: limitWidth)
    }

    public static func textSize(text: String,
                                font: UIFont,
                                limitWidth: CGFloat,
                                limitLineCount: Int = 0,
                                truncationString: NSAttributedString? = nil,
                                color: UIColor = .white,
                                alignment: NSTextAlignment = .left,
                                lineSpacing: CGFloat = 0) -> CGSize {
        let attributedText = self.createAttributedString(text: text,
                                                         font: font,
                                                         color: color,
                                                         alignment: alignment,
                                                         lineSpacing: lineSpacing)
        return self.textSize(attributedText: attributedText,
                             limitWidth: limitWidth,
                             limitLineCount: limitLineCount,
                             truncationString: truncationString)
    }

    public static func fixSize(size: CGSize) -> CGSize {
        return CGSize.init(width: ceil(size.width), height: ceil(size.height))
    }
}

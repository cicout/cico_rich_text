//
//  StyleRangeGroup.swift
//  BudFoundationKit
//
//  Created by Ethan.Li on 2022/2/16.
//

import Foundation
#if os(OSX)
import AppKit
#else
import UIKit
#endif
import SwiftRichString

public typealias AttributedString = NSMutableAttributedString

public struct StyleRangeData {
    public var style: StyleProtocol?
    public var ranges: [NSRange]

    public init(style: StyleProtocol?, ranges: [NSRange]) {
        self.style = style
        self.ranges = ranges
    }
}

public class StyleRangeGroup: StyleProtocol {
    public static let defaultKey = "default_style_range_data_key"

    // The following attributes are ignored for StyleRangeGroup because are read from the sub styles.
    public var attributes: [NSAttributedString.Key: Any] = [:]
    public var fontData: FontData?
    public var textTransforms: [TextTransform]?

    /// Style to apply as base.
    public var baseStyle: StyleProtocol?

    /// Ordered dictionary of the styles and ranges inside the group
    private var styles: [String: StyleRangeData]

    // MARK: - Initialization

    /// Initialize a new `StyleRangeGroup` with a dictionary of styles, ranges and keys.
    /// Note: Ordered is not guarantee, use `init(_ styles:[(String, StyleRangeData)]` if you
    /// need to keep the order of the styles and ranges.
    ///
    /// - Parameters:
    ///   - base: base style applied to the entire string.
    ///   - styles: styles dictionary used for styles and ranges definitions.
    public init(base: StyleProtocol? = nil, _ styles: [String: StyleRangeData] = [:]) {
        self.baseStyle = base
        self.styles = styles
    }

    // MARK: - Public Methods

    public func styleRangeData(for key: String = StyleRangeGroup.defaultKey) -> StyleRangeData? {
        return self.styles[key]
    }

    public func style(for key: String = StyleRangeGroup.defaultKey) -> StyleProtocol? {
        return self.styles[key]?.style
    }

    public func styleRanges(for key: String = StyleRangeGroup.defaultKey) -> [NSRange] {
        return self.styles[key]?.ranges ?? []
    }

    public func set(styleRangeData: StyleRangeData, for key: String = StyleRangeGroup.defaultKey) {
        self.styles[key] = styleRangeData
    }

    /// Set the style with given key.
    /// Order is preserved.
    ///
    /// - Parameters:
    ///   - style: style you want to add.
    ///   - key: unique key of the style.
    public func set(style: StyleProtocol, for key: String = StyleRangeGroup.defaultKey) {
        if var styleRangeData: StyleRangeData = self.styles[key] {
            styleRangeData.style = style
            self.styles[key] = styleRangeData
        } else {
            self.styles[key] = StyleRangeData.init(style: style, ranges: [])
        }
    }

    public func set(styleRanges: [NSRange], for key: String = StyleRangeGroup.defaultKey) {
        if var styleRangeData: StyleRangeData = self.styles[key] {
            styleRangeData.ranges = styleRanges
            self.styles[key] = styleRangeData
        } else {
            self.styles[key] = StyleRangeData.init(style: nil, ranges: styleRanges)
        }
    }

    /// Remove the style and ranges with given key.
    ///
    /// - Parameter key: key of the style and ranges to remove.
    /// - Returns: removed style and ranges instance.
    @discardableResult
    public func remove(for key: String = StyleRangeGroup.defaultKey) -> StyleRangeData? {
        return self.styles.removeValue(forKey: key)
    }

    // MARK: - Rendering Methods

    /// Render given source with styles defined inside the receiver.
    /// Styles are added as sum to any existing
    ///
    /// - Parameters:
    ///   - source: source to render.
    ///   - range: range of characters to render, `nil` to apply rendering to the entire content.
    /// - Returns: attributed string
    public func set(to source: String, range: NSRange?) -> AttributedString {
        let attributed = AttributedString(string: source, attributes: (self.baseStyle?.attributes ?? [:]))
        return self.apply(to: attributed, adding: true, range: range)
    }

    /// Render given source string by appending parsed styles to the existing attributed string.
    ///
    /// - Parameters:
    ///   - source: source attributed string.
    ///   - range: range of parse.
    /// - Returns: same istance of `source` with applied styles.
    public func add(to source: AttributedString, range: NSRange?) -> AttributedString {
        if let base = self.baseStyle {
            source.addAttributes(base.attributes, range: (range ?? NSRange(location: 0, length: source.length)))
        }
        return self.apply(to: source, adding: true, range: range)
    }

    /// Render given source string by replacing existing styles to parsed tags.
    ///
    /// - Parameters:
    ///   - source: source attributed string.
    ///   - range: range of parse.
    /// - Returns: same istance of `source` with applied styles.
    public func set(to source: AttributedString, range: NSRange?) -> AttributedString {
        if let base = self.baseStyle {
            source.setAttributes(base.attributes, range: (range ?? NSRange(location: 0, length: source.length)))
        }
        return self.apply(to: source, adding: false, range: range)
    }

    /// Parse tags and render the attributed string with the styles defined into the receiver.
    ///
    /// - Parameters:
    ///   - attrStr: source attributed string
    ///   - adding: `true` to add styles defined to existing styles, `false` to replace any existing style inside tags.
    ///   - range: range of operation, `nil` for entire string.
    /// - Returns: modified attributed string, same instance of the `source`.
    private func apply(to attrStr: AttributedString, adding: Bool, range: NSRange?) -> AttributedString {
        let allRange = range ?? NSRange(location: 0, length: attrStr.length)

        for styleRangeData in self.styles.values {
            guard let style = styleRangeData.style else { continue }
            for styleRange in styleRangeData.ranges {
                guard let fixedStyleRange = styleRange.intersection(allRange) else { continue }
                if adding {
                    attrStr.addAttributes(style.attributes, range: fixedStyleRange)
                } else {
                    attrStr.setAttributes(style.attributes, range: fixedStyleRange)
                }
            }
        }

        return attrStr
    }
}

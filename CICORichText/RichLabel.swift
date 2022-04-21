//
//  RichLabel.swift
//  CICORichText
//
//  Created by Ethan.Li on 2021/12/18.
//

import UIKit
import SwiftRichString

public class RichLabel: UIView {
    public var tapHighlightTextAction: ((String) -> Void)?
    public var tapNormalTextAction: (() -> Void)?
    public var wrapAction: (() -> Void)?
    public var unwrapAction: (() -> Void)?

    public var highlightType: HighlightType = [] {
        didSet {
            self.refreshHighlighStyle()
        }
    }

    public var highlightTextColor: UIColor = .blue {
        didSet {
            self.refreshHighlighStyle()
        }
    }

    public var enableTap = false {
        didSet {
            self.refreshTapGesture()
        }
    }

    public var sourceAttributedText: NSAttributedString? {
        didSet {
            self.wrapStatus = .normal
            self.updateText()
        }
    }

    public var autoWrapLineCount: Int = 0
    public var autoWrapInfo: WrapInfo?
    public private(set) var wrapStatus = WrapStatus.normal

    public var extraHighlightRanges = [NSRange].init() {
        didSet {
            self.refreshHighlighStyle()
        }
    }

    public var extraHighlightRegexPattern: String = "" {
        didSet {
            self.refreshHighlighStyle()
        }
    }

    private var baseStyle: Style!
    private var highlightStyle: StyleRegEx?
    private var extraHighlightStyle: StyleRangeGroup?
    private var tapGesture: UITapGestureRecognizer?
    private var sourceString: String!
    private var lastSize: CGSize?
    private var labelTextColor: UIColor!

    private var label: ALabel!

    public var lineSpacing: CGFloat = 0 {
        didSet {
            self.refreshBaseStyle()
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.initView()
        self.refreshBaseStyle()
        self.refreshHighlighStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func unwrap() {
        guard self.hasHighlight(), let sourceString = self.sourceString else { return }
        guard self.bounds.width > 0 else {
            self.wrapStatus = .unwrapped
            self.updateText()
            return
        }
        let lineCount = TextAide.lineCount(text: sourceString, font: self.label.font, limitWidth: self.bounds.width)
        guard lineCount > self.autoWrapLineCount else { return }
        self.wrapStatus = .unwrapped
        self.updateText()
    }

    public func wrap() {
        guard self.wrapStatus == .unwrapped else { return }
        self.wrapStatus = .wrapped
        self.updateText()
    }

    private func initView() {
        self.isUserInteractionEnabled = false
        let label = ALabel.init()
        label.numberOfLines = 0
        label.textAlignment = .left
        self.addSubview(label)
        label.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        self.label = label
        self.labelTextColor = label.textColor
    }

    private func refreshBaseStyle() {
        self.baseStyle = Style.init { [weak self] style in
            guard let strongSelf = self else {
                return
            }
            style.font = strongSelf.label.font
            style.color = strongSelf.labelTextColor
            style.alignment = strongSelf.label.textAlignment
            style.lineSpacing = strongSelf.lineSpacing
        }
        self.updateText()
    }

    private func refreshHighlighStyle() {
        guard self.hasHighlight() else {
            self.highlightStyle = nil
            self.extraHighlightStyle = nil
            return
        }

        let regexPattern = self.highlightType.regexPattern(extraRegexPattern: self.extraHighlightRegexPattern)
        let highlightStyle = StyleRegEx.init(pattern: regexPattern) { [weak self] style in
            guard let strongSelf = self else {
                return
            }
            style.color = strongSelf.highlightTextColor
        }

        self.highlightStyle = highlightStyle

        if self.extraHighlightRanges.count > 0 {
            let extraHightlightStyle = StyleRangeGroup.init()
            extraHightlightStyle.set(style: Style.init({ $0.color = self.highlightTextColor }))
            extraHightlightStyle.set(styleRanges: self.extraHighlightRanges)
            self.extraHighlightStyle = extraHightlightStyle
        } else {
            self.extraHighlightStyle = nil
        }

        self.updateText()
    }

    private func updateText() {
        guard self.hasHighlight() else { return }
        self.label.attributedText = self.createAttributedString()
    }

    private func createAttributedString() -> NSAttributedString {
        guard self.hasHighlight() else {
            fatalError("Invalid call")
        }

        let text: String
        if self.wrapStatus.isNormal() {
            text = self.label.text ?? ""
            self.sourceString = text
        } else {
            text = self.sourceString
        }

        let attributedText: NSMutableAttributedString =
        NSMutableAttributedString.init(attributedString: sourceAttributedText ?? text.set(style: self.baseStyle))

        if let highlightStyle = self.highlightStyle {
            attributedText.add(style: highlightStyle)
        }

        if let extraHighlightStyle = self.extraHighlightStyle {
            attributedText.add(style: extraHighlightStyle)
        }

        guard self.autoWrapLineCount > 0 else {
            return attributedText
        }

        let autoWrapInfo = self.autoWrapInfo ?? self.createDefaultWrapInfo()

        if self.wrapStatus.isUnwrapped() {
            attributedText.append(autoWrapInfo.wrapString.text)
            return attributedText
        }
        let limitWidth = self.bounds.width

        let isTruncated =
        TextAide.truncate(attributedText: attributedText,
                          limitWidth: limitWidth,
                          limitLineCount: self.autoWrapLineCount,
                          truncationString: autoWrapInfo.unwrapString.text)

        self.wrapStatus = isTruncated ? .wrapped : .normal

        return attributedText
    }

    private func createDefaultWrapInfo() -> WrapInfo {
        return self.wrapConfig(unwarpText: "More", wrapText: "Hide")
    }

    public func wrapConfig(unwarpText: String, wrapText: String? = nil) -> WrapInfo {
        let colorStyle = Style.init { [weak self] style in
            guard let strongSelf = self else {
                return
            }
            style.font = strongSelf.label.font
            style.color = strongSelf.highlightTextColor
        }

        let unwrapText = NSMutableAttributedString.init(attributedString: "... ".set(style: self.baseStyle))
        unwrapText.append(unwarpText.set(style: colorStyle))
        let unwrapRange = NSRange.init(location: 4, length: unwarpText.utf16.count)
        let unwrapInfo = WrapInfo.WrapString.init(text: unwrapText, tapRange: unwrapRange)

        let wrapStr = wrapText ?? ""
        let wrapText = NSMutableAttributedString.init(attributedString: " ".set(style: self.baseStyle))
        wrapText.append(wrapStr.set(style: colorStyle))
        let wrapRange = NSRange.init(location: 1, length: wrapStr.utf16.count)
        let wrapInfo = WrapInfo.WrapString.init(text: wrapText, tapRange: wrapRange)

        return WrapInfo.init(unwrapString: unwrapInfo, wrapString: wrapInfo)
    }

    private func hasHighlight() -> Bool {
        return !self.highlightType.isNone() || self.autoWrapLineCount > 0 ||
        self.extraHighlightRanges.count > 0 || self.extraHighlightRegexPattern.count > 0
    }
}

extension RichLabel {
    public func highlightTexts() -> [String] {
        return self.highlightMatchs().map { $0.text }
    }

    public func highlightMatchs() -> [MatchString] {
        return self.matchStrings(text: self.sourceString ?? self.label.text ?? "")
    }

    private func matchStrings(text: String) -> [MatchString] {
        guard self.hasHighlight(), let highlightStyle = self.highlightStyle else {
            return []
        }

        var matchStrings: [MatchString] = []

        let nsrange = text.nsrange(fromRange: text.startIndex..<text.endIndex)
        highlightStyle
            .regex
            .enumerateMatches(in: text,
                              options: .init(rawValue: 0),
                              range: nsrange) { result, _, _ in
                if let result = result, let matchText = text.subString(in: result.range) {
                    let matchString = MatchString.init(text: matchText, range: result.range)
                    matchStrings.append(matchString)
                }
            }

        return matchStrings
    }
}

extension RichLabel {
    public override var frame: CGRect {
        get {
            return super.frame
        }
        set {
            super.frame = newValue
            self.refreshSize()
        }
    }

    public override var bounds: CGRect {
        get {
            return super.bounds
        }
        set {
            super.bounds = newValue
            self.refreshSize()
        }
    }

    private func refreshSize() {
        guard let lastSize = self.lastSize else {
            self.lastSize = self.bounds.size
            return
        }

        if lastSize.equalTo(self.bounds.size) {
            return
        }

        self.lastSize = self.bounds.size

        guard self.autoWrapLineCount > 0 else { return }

        self.updateText()
        self.layoutIfNeeded()
    }
}

extension RichLabel {
    private func refreshTapGesture() {
        if !self.enableTap {
            self.isUserInteractionEnabled = false
            if let tap = self.tapGesture {
                self.removeGestureRecognizer(tap)
                self.tapGesture = nil
            }
            return
        }

        self.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer.init(target: self, action: #selector(onTapAction(tap:)))
        self.addGestureRecognizer(tap)
        self.tapGesture = tap
    }

    private func onTapAction(startChar: Int) {
        if self.autoWrapLineCount > 0 {
            let textRange = NSRange.init(location: 0, length: ((self.label.text ?? "") as NSString).length)
            let autoWrapInfo = self.autoWrapInfo ?? self.createDefaultWrapInfo()

            if self.wrapStatus.isWrapped(), var tapRange = autoWrapInfo.unwrapString.tapRange {
                tapRange.location =
                textRange.length - (autoWrapInfo.unwrapString.text.string as NSString).length + tapRange.location
                if tapRange.lowerBound <= startChar, tapRange.upperBound - 1 >= startChar {
                    self.wrapStatus = .unwrapped
                    self.updateText()
                    self.unwrapAction?()
                    return
                }
            } else if self.wrapStatus.isUnwrapped(), var tapRange = autoWrapInfo.wrapString.tapRange {
                tapRange.location =
                textRange.length - (autoWrapInfo.wrapString.text.string as NSString).length + tapRange.location
                if tapRange.lowerBound <= startChar, tapRange.upperBound - 1 >= startChar {
                    self.wrapStatus = .wrapped
                    self.updateText()
                    self.wrapAction?()
                    return
                }
            }
        }

        let matchs = self.highlightMatchs()
        for match in matchs where
        match.range.lowerBound <= startChar && match.range.upperBound - 1 >= startChar {
            self.tapHighlightTextAction?(match.text)
            return
        }

        if let extraHighlightStyle = self.extraHighlightStyle, let sourceString = self.sourceString {
            let allRange = NSRange.init(location: 0, length: (sourceString as NSString).length)
            let fixedRanges = extraHighlightStyle.styleRanges().compactMap { $0.intersection(allRange) }
            for range in fixedRanges {
                if range.lowerBound <= startChar,
                    range.upperBound - 1 >= startChar,
                    let text = sourceString.subString(in: range) {
                    self.tapHighlightTextAction?(text)
                    return
                }
            }
        }

        self.tapNormalTextAction?()
    }

    @objc private func onTapAction(tap: UITapGestureRecognizer) {
        guard self.enableTap, self.hasHighlight() else {
            self.tapNormalTextAction?()
            return
        }

        let tapLocation = tap.location(in: self.label)
        let textOffset = self.label.textOffset()
        let fixedTapLocation = tapLocation.offset(dx: -textOffset.x, dy: -textOffset.y)

        let startChar: Int = self.label.layoutManager.characterIndex(for: fixedTapLocation,
                                                                        in: self.label.textContainer,
                                                                        fractionOfDistanceBetweenInsertionPoints: nil)

        let glythRange = NSRange.init(location: startChar, length: 1)
        let glythRect = self.label.layoutManager.boundingRect(forGlyphRange: glythRange, in: self.label.textContainer)
        let fixedGlythRect = glythRect.inset(by: .init(top: -10, left: -10, bottom: -10, right: -10))
        guard fixedGlythRect.contains(fixedTapLocation) else {
            self.tapNormalTextAction?()
            return
        }

        self.onTapAction(startChar: startChar)
    }
}

extension RichLabel {
    public var font: UIFont? {
        get {
            return self.label.font
        }
        set {
            self.label.font = newValue
            self.refreshBaseStyle()
        }
    }

    public var textColor: UIColor? {
        get {
            return self.label.textColor
        }
        set {
            self.label.textColor = newValue
            self.labelTextColor = newValue
            self.refreshBaseStyle()
        }
    }

    public var text: String! {
        get {
            return self.label.text
        }
        set {
            self.label.text = newValue
            self.wrapStatus = .normal
            self.updateText()
        }
    }

    public var textAlignment: NSTextAlignment {
        get {
            return self.label.textAlignment
        }
        set {
            self.label.textAlignment = newValue
            self.refreshBaseStyle()
        }
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        return self.label.sizeThatFits(size)
    }
}

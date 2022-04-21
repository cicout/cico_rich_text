//
//  RichTextView.swift
//  CICORichText
//
//  Created by Ethan.Li on 2021/11/24.
//

import UIKit
import SnapKit
import SwiftRichString

public class RichTextView: UIView {
    public var shouldBeginEditingAction: (() -> Bool)?
    public var returnAction: (() -> Void)?
    public var textDidChangeAction: ((String) -> Void)?
    public var shouldChangeTextAction: ((NSRange, String) -> Bool)?
    public var creatingTopicAction: ((String) -> Void)?
    public var startCreatingTopicAction: (() -> Void)?
    public var createTopicDoneAction: ((String) -> Void)?
    public var atUserAction: (() -> Void)?
    public var textReachLimitCountAction: (() -> Void)?
    public var textReachLimitLineAction: (() -> Void)?
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

    public var placeholder: String? {
        get {
            return self.placeHolderLabel.text
        }
        set {
            self.placeHolderLabel.text = newValue
        }
    }

    public var placeholderTextColor: UIColor? {
        get {
            return self.placeHolderLabel.textColor
        }
        set {
            self.placeHolderLabel.textColor = newValue
        }
    }

    public var enableNewLine = true

    public var textLimitCount: Int = 0

    public var textLimitLine: Int = 0

    public var enableTap = false {
        didSet {
            self.refreshTapGesture()
        }
    }

    public var autoWrapLineCount: Int = 0
    public var autoWrapInfo: WrapInfo?

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
    private var isCreatingTopic: Bool {
        return self.topicStartLocation > 0
    }
    private var topicStartLocation: Int = 0
    private var isUpdatingText = false
    private var tapGesture: UITapGestureRecognizer?
    private var wrapStatus = WrapStatus.normal
    private var sourceString: String!
    private var lastSize: CGSize?

    private var textView: UITextView!
    private var placeHolderLabel: UILabel!

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.initView()
        self.refreshBaseStyle()
        self.refreshHighlighStyle()
    }

    public var lineSpacing: CGFloat = 0 {
        didSet {
            self.refreshBaseStyle()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func unwrap() {
        guard self.hasHighlight(), let sourceString = self.sourceString else { return }
        guard self.bounds.width > 0 else {
            self.wrapStatus = .unwrapped
            self.updateText(resumeSelectedRange: nil)
            return
        }
        let lineCount = TextAide.lineCount(text: sourceString,
                                           font: self.textView.font ?? .systemFont(ofSize: 16),
                                           limitWidth: self.bounds.width)
        guard lineCount > self.autoWrapLineCount else { return }
        self.wrapStatus = .unwrapped
        self.updateText(resumeSelectedRange: nil)
    }

    public func wrap() {
        guard self.wrapStatus == .unwrapped else { return }
        self.wrapStatus = .wrapped
        self.updateText(resumeSelectedRange: nil)
    }

    private func initView() {
        let textView = UITextView.init()
        textView.backgroundColor = .clear
        textView.delegate = self
        self.addSubview(textView)
        textView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        self.textView = textView

        let label = UILabel.init()
        label.font = textView.font
        label.textColor = UIColor.gray
        self.addSubview(label)
        self.placeHolderLabel = label

        self.refreshPlaceholderLayout()
    }

    private func updateText(resumeSelectedRange: NSRange?, notifyTextChange: Bool = true) {
        if self.hasHighlight() {
            self.isUpdatingText = true

            self.textView.attributedText = self.createAttributedString()
            if let resumeSelectedRange = resumeSelectedRange {
                self.textView.selectedRange = resumeSelectedRange
            }

            self.isUpdatingText = false
        }

        if self.textView.text.count > 0 {
            self.placeHolderLabel.isHidden = true
        } else {
            self.placeHolderLabel.isHidden = false
        }

        if notifyTextChange {
            self.textDidChangeAction?(self.textView.text)
        }
    }

    private func handleDeleteText(range: NSRange) -> Bool {
        guard let text = self.textView.text, self.hasHighlight() else {
            return true
        }

        if self.isCreatingTopic, self.textView.selectedRange.location >= self.topicStartLocation {
            let nsrange = NSRange(location: self.topicStartLocation,
                                  length: self.textView.selectedRange.location - self.topicStartLocation)
            if let topic = self.textView.text.subString(in: nsrange),
               !topic.contains("#"),
               !topic.contains(" "),
               !topic.contains("@") {
                return true
            }
        }

        var fixedRange = range

        let matchs = self.highlightMatchs()
        let reverseRanges = matchs.map { $0.range }.reversed()
        reverseRanges.forEach { highlightRange in
            let isIntersect: Bool = highlightRange.intersection(fixedRange)?.length ?? 0 > 0
            if isIntersect || highlightRange.upperBound == fixedRange.location {
                fixedRange = fixedRange.union(highlightRange)
            }
        }

        if fixedRange.location != range.location || fixedRange.length != range.length,
           let textRange = text.rangeFrom(nsRange: fixedRange) {
            self.textView.text = text.replacingCharacters(in: textRange, with: "")
            self.updateText(resumeSelectedRange: NSRange.init(location: fixedRange.location, length: 0))
            return false
        }

        return true
    }

    private func createAttributedString() -> NSAttributedString {
        guard self.hasHighlight() else {
            fatalError("Invalid call")
        }

        let text: String
        if self.wrapStatus.isNormal() {
            text = self.textView.text ?? ""
            self.sourceString = text
        } else {
            text = self.sourceString
        }

        let attributedText: NSMutableAttributedString = text.set(style: self.baseStyle)

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

        let limitWidth = self.bounds.inset(by: self.textContainerInset).width - 2 * self.lineFragmentPadding

        let isTruncated =
        TextAide.truncate(attributedText: attributedText,
                          limitWidth: limitWidth,
                          limitLineCount: self.autoWrapLineCount,
                          truncationString: autoWrapInfo.unwrapString.text)

        self.wrapStatus = isTruncated ? .wrapped : .normal

        return attributedText
    }

    private func createDefaultWrapInfo() -> WrapInfo {
        let colorStyle = Style.init { [weak self] style in
            guard let strongSelf = self else {
                return
            }
            style.font = strongSelf.textView.font
            style.color = strongSelf.highlightTextColor
        }

        let unwrapText = NSMutableAttributedString.init(attributedString: "... ".set(style: self.baseStyle))
        unwrapText.append("More".set(style: colorStyle))
        let unwrapRange = NSRange.init(location: 4, length: 4)
        let unwrapInfo = WrapInfo.WrapString.init(text: unwrapText, tapRange: unwrapRange)

        let wrapText = NSMutableAttributedString.init(attributedString: " ".set(style: self.baseStyle))
        wrapText.append("Hide".set(style: colorStyle))
        let wrapRange = NSRange.init(location: 1, length: 4)
        let wrapInfo = WrapInfo.WrapString.init(text: wrapText, tapRange: wrapRange)

        return WrapInfo.init(unwrapString: unwrapInfo, wrapString: wrapInfo)
    }

    private func refreshPlaceholderLayout() {
        self.placeHolderLabel.snp.remakeConstraints { make in
            let offset = self.textView.textContainerInset.left + self.textView.textContainer.lineFragmentPadding + 1
            make.left.equalToSuperview().offset(offset)
            make.top.equalToSuperview().offset(self.textView.textContainerInset.top)
            make.right.lessThanOrEqualToSuperview().offset(-self.textView.textContainerInset.right)
        }
    }

    private func hasHighlight() -> Bool {
        return !self.highlightType.isNone() || self.autoWrapLineCount > 0 ||
        self.extraHighlightRanges.count > 0 || self.extraHighlightRegexPattern.count > 0
    }

    private func fixTextForLimitIfNeeded() {
        if self.textLimitCount > 0 && self.textView.text.count > self.textLimitCount {
            self.textView.text = self.textView.text.substring(from: 0, length: self.textLimitCount)
            self.textReachLimitCountAction?()
        }
    }
}

extension RichTextView {
    public func highlightTexts() -> [String] {
        return self.highlightMatchs().map { $0.text }
    }

    public func highlightMatchs() -> [MatchString] {
        return self.matchStrings(text: self.sourceString ?? self.textView.text)
    }

    public func replaceCurrentText(_ topic: String) {
        guard topic.count > 0 else {
            return
        }

        var fixedTopic = topic
        if !fixedTopic.hasPrefix("#") {
            fixedTopic = "#\(fixedTopic)"
        }
        if !fixedTopic.hasSuffix(" ") {
            fixedTopic = "\(fixedTopic) "
        }

        let currentLocation = self.textView.selectedRange.location
        let subRange = NSRange(location: 0, length: currentLocation)
        let subText = self.textView.text.subString(in: subRange)
        let currentTopic = subText?.split(separator: "#").last?.string ?? ""
        let fixedCurrentTopic = "#\(currentTopic)"

        let currentTopicLength: Int = (fixedCurrentTopic as NSString).length
        let leftLength: Int = max(currentLocation - currentTopicLength, 0)
        let leftRange = NSRange(location: 0, length: leftLength)
        let subTextLeft = subText?.subString(in: leftRange) ?? ""

        let textLength: Int = (self.textView.text as NSString).length
        let rightLength: Int = max(textLength - currentLocation, 0)
        let rightRange = NSRange(location: currentLocation, length: rightLength)
        let subTextRight = self.textView.text.subString(in: rightRange) ?? ""

        let newText = subTextLeft + fixedTopic + subTextRight
        self.textView.text = newText
        self.fixTextForLimitIfNeeded()
        self.updateText(resumeSelectedRange: self.textView.selectedRange)
    }

    public func replaceCurrentTopic(_ topic: String) {
        guard self.isCreatingTopic else {
            return
        }

        self.replaceCurrentText(topic)
        self.finishCreatingTopic()
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

extension RichTextView {
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

        self.updateText(resumeSelectedRange: self.textView.selectedRange)
        self.layoutIfNeeded()
    }
}

extension RichTextView {
    private func refreshBaseStyle() {
        self.baseStyle = Style.init { [weak self] style in
            guard let strongSelf = self else {
                return
            }
            style.font = strongSelf.textView.font
            style.color = strongSelf.textView.textColor
            style.lineSpacing = strongSelf.lineSpacing
        }

        self.updateText(resumeSelectedRange: self.textView.selectedRange, notifyTextChange: false)
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

        self.updateText(resumeSelectedRange: self.textView.selectedRange, notifyTextChange: false)
    }
}

extension RichTextView {
    private func currentTopic() -> String {
        guard self.isCreatingTopic, self.textView.selectedRange.location >= self.topicStartLocation else {
            return ""
        }

        let nsrange = NSRange(location: self.topicStartLocation,
                              length: self.textView.selectedRange.location - self.topicStartLocation)

        return self.textView.text.subString(in: nsrange) ?? ""
    }

    private func updateCreatingTopicIfNeeded() {
        guard self.highlightType.hasSharp(), self.isCreatingTopic else {
            return
        }

        self.creatingTopicAction?(self.currentTopic())
    }

    private func startCreatingTopic(location: Int) {
        guard self.highlightType.hasSharp() else { return }
        self.topicStartLocation = location
        self.startCreatingTopicAction?()
    }

    private func finishCreatingTopic() {
        guard self.highlightType.hasSharp(), self.isCreatingTopic else {
            return
        }
        let topic = self.currentTopic()
        self.topicStartLocation = 0
        self.createTopicDoneAction?(topic)
    }

    private func handleChangeSelectionForTopic() -> Bool {
        guard self.isCreatingTopic else { return false }

        guard self.textView.selectedRange.location >= self.topicStartLocation else {
            self.finishCreatingTopic()
            return false
        }

        let nsrange = NSRange(location: self.topicStartLocation,
                              length: self.textView.selectedRange.location - self.topicStartLocation)

        if let topic = self.textView.text.subString(in: nsrange),
           !topic.contains("#"),
           !topic.contains(" "),
           !topic.contains("@"),
           !topic.contains("\n") {
            self.updateCreatingTopicIfNeeded()
            return true
        } else {
            self.finishCreatingTopic()
            return false
        }
    }
}

extension RichTextView {
    private func refreshTapGesture() {
        if !self.enableTap {
            if let tap = self.tapGesture {
                self.textView.removeGestureRecognizer(tap)
                self.tapGesture = nil
            }
            return
        }

        let tap = UITapGestureRecognizer.init(target: self, action: #selector(onTapAction(tap:)))
        self.textView.addGestureRecognizer(tap)
        self.tapGesture = tap
    }

    private func onTapAction(startLocation: Int) {
        if self.autoWrapLineCount > 0 {
            let textRange = NSRange.init(location: 0, length: (self.textView.text as NSString).length)
            let autoWrapInfo = self.autoWrapInfo ?? self.createDefaultWrapInfo()

            if self.wrapStatus.isWrapped(), var tapRange = autoWrapInfo.unwrapString.tapRange {
                tapRange.location =
                textRange.length - (autoWrapInfo.unwrapString.text.string as NSString).length + tapRange.location
                if tapRange.lowerBound <= startLocation, tapRange.upperBound >= startLocation {
                    self.wrapStatus = .unwrapped
                    self.updateText(resumeSelectedRange: self.textView.selectedRange)
                    self.unwrapAction?()
                    return
                }
            } else if self.wrapStatus.isUnwrapped(), var tapRange = autoWrapInfo.wrapString.tapRange {
                tapRange.location =
                textRange.length - (autoWrapInfo.wrapString.text.string as NSString).length + tapRange.location
                if tapRange.lowerBound <= startLocation, tapRange.upperBound >= startLocation {
                    self.wrapStatus = .wrapped
                    self.updateText(resumeSelectedRange: self.textView.selectedRange)
                    self.wrapAction?()
                    return
                }
            }
        }

        let matchs = self.highlightMatchs()
        for match in matchs where
        match.range.lowerBound <= startLocation && match.range.upperBound >= startLocation {
            self.tapHighlightTextAction?(match.text)
            return
        }

        if let extraHighlightStyle = self.extraHighlightStyle, let sourceString = self.sourceString {
            let allRange = NSRange.init(location: 0, length: (sourceString as NSString).length)
            let fixedRanges = extraHighlightStyle.styleRanges().compactMap { $0.intersection(allRange) }
            for range in fixedRanges {
                if range.lowerBound <= startLocation,
                    range.upperBound >= startLocation,
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
            return
        }

        let tapLocation = tap.location(in: self.textView)

        guard let startPosition = self.textView.closestPosition(to: tapLocation) else {
            return
        }

        let startLocation = self.textView.offset(from: self.textView.beginningOfDocument, to: startPosition)

        // handle out of first/last location
        let textOffset = CGPoint.init(x: self.lineFragmentPadding + self.textContainerInset.left,
                                      y: self.textContainerInset.top)
        let fixedTapLocation = tapLocation.offset(dx: -textOffset.x, dy: -textOffset.y)
        let glythRange = NSRange.init(location: startLocation, length: 1)
        let glythRect =
        self.textView.layoutManager.boundingRect(forGlyphRange: glythRange, in: self.textView.textContainer)
        let fixedGlythRect = glythRect.inset(by: .init(top: -10, left: -10, bottom: -10, right: -10))
        guard fixedGlythRect.contains(fixedTapLocation) else {
            self.tapNormalTextAction?()
            return
        }

        self.onTapAction(startLocation: startLocation)
    }
}

extension RichTextView {

    public var lineFragmentPadding: CGFloat {
        get {
            return self.textView.textContainer.lineFragmentPadding
        }
        set {
            self.textView.textContainer.lineFragmentPadding = newValue
            self.refreshPlaceholderLayout()
        }
    }

    public var textViewContentInset: UIEdgeInsets {
        get {
            return self.textView.contentInset
        }
        set {
            self.textView.contentInset = newValue
        }
    }

    public var font: UIFont? {
        get {
            return self.textView.font
        }
        set {
            self.textView.font = newValue
            self.placeHolderLabel.font = newValue
            self.refreshBaseStyle()
        }
    }

    public var textViewTintColor: UIColor? {
        get {
            return self.textView.tintColor
        }
        set {
            self.textView.tintColor = newValue
        }
    }

    public var textColor: UIColor? {
        get {
            return self.textView.textColor
        }
        set {
            self.textView.textColor = newValue
            self.refreshBaseStyle()
        }
    }

    public var text: String! {
        get {
            return self.textView.text
        }
        set {
            self.textView.text = newValue
            self.wrapStatus = .normal
            self.updateText(resumeSelectedRange: nil)
        }
    }

    public var isScrollEnabled: Bool {
        get {
            return self.textView.isScrollEnabled
        }
        set {
            self.textView.isScrollEnabled = newValue
        }
    }

    public var showsHorizontalScrollIndicator: Bool {
        get {
            return self.textView.showsHorizontalScrollIndicator
        }
        set {
            self.textView.showsHorizontalScrollIndicator = newValue
        }
    }

    public var showsVerticalScrollIndicator: Bool {
        get {
            return self.textView.showsVerticalScrollIndicator
        }
        set {
            self.textView.showsVerticalScrollIndicator = newValue
        }
    }

    public var keyboardType: UIKeyboardType {
        get {
            return self.textView.keyboardType
        }
        set {
            self.textView.keyboardType = newValue
        }
    }

    public var returnKeyType: UIReturnKeyType {
        get {
            return self.textView.returnKeyType
        }
        set {
            self.textView.returnKeyType = newValue
        }
    }

    public var textContainerInset: UIEdgeInsets {
        get {
            return self.textView.textContainerInset
        }
        set {
            self.textView.textContainerInset = newValue
            self.refreshPlaceholderLayout()
        }
    }

    public var isEditable: Bool {
        get {
            return self.textView.isEditable
        }
        set {
            self.textView.isEditable = newValue
        }
    }

    public var selectedRange: NSRange {
        return self.textView.selectedRange
    }

    public var isSelectable: Bool {
        get {
            return self.textView.isSelectable
        }
        set {
            self.textView.isSelectable = newValue
        }
    }

    public var textAlignment: NSTextAlignment {
        get {
            self.textView.textAlignment
        }
        set {
            self.textView.textAlignment = newValue
        }
    }

    public override var isFirstResponder: Bool {
        return self.textView.isFirstResponder
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        return self.textView.becomeFirstResponder()
    }

    @discardableResult
    public override func resignFirstResponder() -> Bool {
        return self.textView.resignFirstResponder()
    }

    public func insertText(_ text: String) {
        self.textView.insertText(text)

        if text == "#" && self.highlightType.hasSharp() {
            if self.isCreatingTopic {
                self.finishCreatingTopic()
            }
            self.startCreatingTopic(location: self.textView.selectedRange.location)
        } else {
            self.finishCreatingTopic()
        }
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        return self.textView.sizeThatFits(size)
    }
}

extension RichTextView: UITextViewDelegate {
    public func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        return self.shouldBeginEditingAction?() ?? true
    }

    public func textView(_ textView: UITextView,
                         shouldChangeTextIn range: NSRange,
                         replacementText text: String) -> Bool {
        if text == "\n" {
            self.returnAction?()
            if !self.enableNewLine {
                return false
            }
        }

        if text == "#" && self.highlightType.hasSharp() {
            self.finishCreatingTopic()
            self.startCreatingTopic(location: self.textView.selectedRange.location + 1)
        }

        if text == "@" {
            if self.highlightType.hasSharp() {
                self.finishCreatingTopic()
            }

            if self.highlightType.hasAt() {
                self.atUserAction?()
                return false
            }
        }

        if text == " " && self.highlightType.hasSharp() {
            self.finishCreatingTopic()
        }

        if text == "" {
            let result = self.handleDeleteText(range: range)
            if !result {
                return false
            }
        }

        return self.shouldChangeTextAction?(range, text) ?? true
    }

    public func textViewDidChange(_ textView: UITextView) {
        guard nil == textView.markedTextRange else {
            if self.textView.text.count > 0 {
                self.placeHolderLabel.isHidden = true
            } else {
                self.placeHolderLabel.isHidden = false
            }
            return
        }

        self.fixTextForLimitIfNeeded()

        self.updateText(resumeSelectedRange: self.textView.selectedRange)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard nil == textView.markedTextRange,
              !self.isUpdatingText,
              textView.selectedRange.length == 0,
              let text = self.textView.text else {
            return
        }

        let needReturn = self.handleChangeSelectionForTopic()
        if needReturn {
            return
        }

        guard self.hasHighlight(), let highlightStyle = self.highlightStyle else {
            return
        }

        let textLength = (text as NSString).length

        // Move selectedRange out of highlightTexts.
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

        matchStrings.forEach { matchString in
            guard matchString.range.location < textView.selectedRange.location,
               textView.selectedRange.location <= matchString.range.upperBound else {
                   return
            }
            let location: Int = min(matchString.range.upperBound + 1, textLength)
            if textView.selectedRange.location != location {
                textView.selectedRange = NSRange.init(location: location, length: 0)
            }
        }
    }
}

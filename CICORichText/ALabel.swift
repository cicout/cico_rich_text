//
//  ALabel.swift
//  CICORichText
//
//  Created by Ethan.Li on 2021/12/24.
//

import UIKit

public class ALabel: UILabel {
    lazy private(set) var textStorage: NSTextStorage = {
        let storage = NSTextStorage.init()
        storage.addLayoutManager(self.layoutManager)
        return storage
    }()

    lazy private(set) var layoutManager: NSLayoutManager = {
        let layout = NSLayoutManager.init()
        layout.addTextContainer(self.textContainer)
        return layout
    }()

    lazy private(set) var textContainer: NSTextContainer = {
        let container = NSTextContainer.init()
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = self.numberOfLines
        container.lineBreakMode = self.lineBreakMode
        container.size = self.bounds.size
        return container
    }()

    public override var attributedText: NSAttributedString? {
        get {
            return super.attributedText
        }
        set {
            super.attributedText = newValue
            self.textStorage.setAttributedString(newValue ?? NSAttributedString.init(string: ""))
        }
    }

    public override var frame: CGRect {
        get {
            return super.frame
        }
        set {
            super.frame = newValue
            self.refreshSize(size: newValue.size)
        }
    }

    public override var bounds: CGRect {
        get {
            return super.bounds
        }
        set {
            super.bounds = newValue
            self.refreshSize(size: newValue.size)
        }
    }

    public override func drawText(in rect: CGRect) {
        let glyphRange = self.layoutManager.glyphRange(for: self.textContainer)
        let offset = self.textOffset()
        self.layoutManager.drawBackground(forGlyphRange: glyphRange, at: offset)
        self.layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: offset)
    }

    public func textOffset() -> CGPoint {
        guard let attributedText = self.attributedText else { return .zero }
        let textSize = TextAide.textSize(attributedText: attributedText, limitWidth: self.textContainer.size.width)
        return CGPoint.init(x: 0, y: (self.bounds.size.height - textSize.height) / 2.0)
    }

    private func refreshSize(size: CGSize) {
        self.textContainer.size = size
    }
}

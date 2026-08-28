#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: generate_acknowledgements.swift input.rtf output.pdf\n".utf8))
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let attributedString = try NSAttributedString(
    url: inputURL,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
)

let printInfo = NSPrintInfo()
printInfo.paperSize = NSSize(width: 612, height: 792)
printInfo.topMargin = 54
printInfo.bottomMargin = 54
printInfo.leftMargin = 54
printInfo.rightMargin = 54
printInfo.horizontalPagination = .fit
printInfo.verticalPagination = .automatic

let contentWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
let textStorage = NSTextStorage(attributedString: attributedString)
let layoutManager = NSLayoutManager()
let textContainer = NSTextContainer(
    containerSize: NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
)
textContainer.widthTracksTextView = true
layoutManager.addTextContainer(textContainer)
textStorage.addLayoutManager(layoutManager)
layoutManager.ensureLayout(for: textContainer)

let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
let textView = NSTextView(
    frame: NSRect(x: 0, y: 0, width: contentWidth, height: max(usedHeight, 1)),
    textContainer: textContainer
)
textView.isEditable = false
textView.drawsBackground = false

let output = NSMutableData()
let operation = NSPrintOperation.pdfOperation(
    with: textView,
    inside: textView.bounds,
    to: output
)
operation.printInfo = printInfo
operation.showsPrintPanel = false
operation.showsProgressPanel = false

guard operation.run() else {
    FileHandle.standardError.write(Data("error: PDF generation failed\n".utf8))
    exit(1)
}

try (output as Data).write(to: outputURL, options: .atomic)

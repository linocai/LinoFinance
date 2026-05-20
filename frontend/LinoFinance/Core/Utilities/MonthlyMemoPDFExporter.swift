import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum MonthlyMemoPDFExporter {
    @MainActor
    static func export(memo: AIMemoDTO, summary: String) throws -> URL {
        let url = exportURL(for: memo)
        try render(text: printableText(for: memo, summary: summary), to: url)
        return url
    }

    private static func exportURL(for memo: AIMemoDTO) -> URL {
#if os(macOS)
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
#else
        let directory = FileManager.default.temporaryDirectory
#endif
        return directory.appendingPathComponent("LinoFinance-月报-\(periodName(for: memo)).pdf")
    }

    private static func periodName(for memo: AIMemoDTO) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: memo.periodStart)
    }

    private static func printableText(for memo: AIMemoDTO, summary: String) -> String {
        """
        LinoFinance 月度财务故事
        周期：\(FinanceFormatter.mediumDate(memo.periodStart)) - \(FinanceFormatter.mediumDate(memo.periodEnd))
        状态：\(memo.status.financeStatusTitle)
        生成器：\(memo.generator)

        \(summary)
        """
    }

    private static func render(text: String, to url: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let contentRect = pageRect.insetBy(dx: 54, dy: 56)
        let attributes = textAttributes()
        let attributed = NSAttributedString(string: text, attributes: attributes)
#if os(iOS)
        UIGraphicsBeginPDFContextToFile(url.path, pageRect, nil)
        UIGraphicsBeginPDFPage()
        attributed.draw(in: contentRect)
        UIGraphicsEndPDFContext()
#elseif os(macOS)
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw MonthlyMemoPDFExportError.unableToCreateContext
        }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributed.draw(in: contentRect)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
#endif
    }

    private static func textAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
#if os(macOS)
        return [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
#else
        return [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
        ]
#endif
    }
}

enum MonthlyMemoPDFExportError: LocalizedError {
    case unableToCreateContext

    var errorDescription: String? {
        "无法创建 PDF 文件。"
    }
}

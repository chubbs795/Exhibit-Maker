// Exhibit Maker — builds the combined PDF: exhibit tab pages, first-page exhibit
// stamps and Bates numbers, drawn permanently into the page content.
import AppKit
import PDFKit

struct RenderJob {
    let files: [URL]
    let labels: [String]          // "EXHIBIT 1", "EXHIBIT 2", …
    let descriptions: [String]
    let stampFirstPage: Bool
    let descriptionOnTabPages: Bool
    let batesOnTabPages: Bool
    let batesStart: Int
    let bates: (Int) -> String    // formats a Bates number, e.g. CITY000001
}

enum RenderError: LocalizedError {
    case cannotOpen(String)
    case cannotCreateOutput
    var errorDescription: String? {
        switch self {
        case .cannotOpen(let name): return "Couldn't open \(name). It may be damaged or password-protected."
        case .cannotCreateOutput: return "Couldn't create the output PDF."
        }
    }
}

final class ExhibitRenderer {
    private let letter = CGRect(x: 0, y: 0, width: 612, height: 792)   // 8.5 x 11 in

    /// Returns the total number of pages written.
    func render(_ job: RenderJob, to outputURL: URL, progress: (Double) -> Void) throws -> Int {
        let docs = try job.files.map { url -> PDFDocument in
            guard let doc = PDFDocument(url: url), !doc.isLocked else { throw RenderError.cannotOpen(url.lastPathComponent) }
            return doc
        }
        let totalSourcePages = max(1, docs.reduce(0) { $0 + $1.pageCount })

        // Write to a temporary file first, so choosing one of the inputs as the output is safe.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let info = [kCGPDFContextCreator as String: "Exhibit Maker"] as CFDictionary
        guard let ctx = CGContext(temp as CFURL, mediaBox: nil, info) else { throw RenderError.cannotCreateOutput }

        var batesNumber = job.batesStart
        var pagesWritten = 0
        var sourcePagesDone = 0

        for (i, doc) in docs.enumerated() {
            let label = job.labels[i]

            // 1. Exhibit tab (slip-sheet) page.
            beginPage(ctx, letter)
            drawTabPage(label: label, description: job.descriptionOnTabPages ? job.descriptions[i] : nil, in: letter)
            if job.batesOnTabPages {
                drawStamp(job.bates(batesNumber), font: font(10), atTop: false, bordered: false, in: letter)
                batesNumber += 1
            }
            endPage(ctx)
            pagesWritten += 1

            // 2. The exhibit's own pages, with Bates numbers and a first-page exhibit stamp.
            for p in 0..<doc.pageCount {
                guard let page = doc.page(at: p) else { continue }
                let crop = page.bounds(for: .cropBox)
                let sideways = abs(page.rotation) % 180 == 90
                let box = CGRect(x: 0, y: 0,
                                 width: sideways ? crop.height : crop.width,
                                 height: sideways ? crop.width : crop.height)
                beginPage(ctx, box)
                ctx.saveGState()
                page.transform(ctx, for: .cropBox)      // honors rotation and crop
                page.draw(with: .cropBox, to: ctx)      // includes annotations and form fields
                ctx.restoreGState()
                if p == 0 && job.stampFirstPage {
                    drawStamp(label, font: font(14), atTop: true, bordered: true, in: box)
                }
                drawStamp(job.bates(batesNumber), font: font(10), atTop: false, bordered: false, in: box)
                batesNumber += 1
                endPage(ctx)
                pagesWritten += 1
                sourcePagesDone += 1
                progress(Double(sourcePagesDone) / Double(totalSourcePages))
            }
        }
        ctx.closePDF()

        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }
        try fm.moveItem(at: temp, to: outputURL)
        return pagesWritten
    }

    // MARK: Page helpers

    private func beginPage(_ ctx: CGContext, _ box: CGRect) {
        var mediaBox = box
        let boxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size) as CFData
        ctx.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    }

    private func endPage(_ ctx: CGContext) {
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
    }

    private func font(_ size: CGFloat) -> NSFont {
        NSFont(name: "Helvetica-Bold", size: size) ?? .boldSystemFont(ofSize: size)
    }

    /// Draws text on a white background in the bottom-right (Bates) or top-right (exhibit) corner.
    private func drawStamp(_ text: String, font: NSFont, atTop: Bool, bordered: Bool, in box: CGRect) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let size = string.size()
        let pad: CGFloat = bordered ? 6 : 3
        let margin: CGFloat = atTop ? 22 : 16
        let rect = CGRect(x: box.maxX - margin - size.width - pad * 2,
                          y: atTop ? box.maxY - margin - size.height - pad * 2 : box.minY + margin,
                          width: size.width + pad * 2,
                          height: size.height + pad * 2)
        NSColor.white.setFill()
        NSBezierPath(rect: rect).fill()
        if bordered {
            NSColor.black.setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.75, dy: 0.75))
            border.lineWidth = 1.5
            border.stroke()
        }
        string.draw(at: CGPoint(x: rect.minX + pad, y: rect.minY + pad))
    }

    private func drawTabPage(label: String, description: String?, in box: CGRect) {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let title = NSAttributedString(string: label, attributes: [
            .font: font(54), .foregroundColor: NSColor.black, .paragraphStyle: centered])
        let titleHeight = title.size().height
        let titleRect = CGRect(x: 36, y: box.midY - titleHeight / 2 + 20, width: box.width - 72, height: titleHeight)
        title.draw(in: titleRect)

        if let description, !description.isEmpty {
            let body = NSAttributedString(string: description, attributes: [
                .font: NSFont(name: "Helvetica", size: 16) ?? .systemFont(ofSize: 16),
                .foregroundColor: NSColor.black, .paragraphStyle: centered])
            let bodyRect = CGRect(x: 72, y: titleRect.minY - 110, width: box.width - 144, height: 90)
            body.draw(with: bodyRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}

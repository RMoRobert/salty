//
//  RecipeOCRService.swift
//  Salty
//
//  Created by Robert on 7/13/25.
//

import Vision
import Foundation
import OSLog
import PDFKit
import CoreGraphics

#if os(iOS)
import VisionKit
import UIKit
#elseif os(macOS)
import AppKit
#endif


enum RecipeOCRError: Error, LocalizedError, Equatable {
    case invalidImage
    case invalidDocument
    case noTextFound
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The provided image is invalid."
        case .invalidDocument:
            return "The PDF could not be read."
        case .noTextFound:
            return "No text was found in the image."
        case .processingFailed:
            return "Failed to process the image for text recognition."
        }
    }
}

@MainActor
@Observable
class RecipeOCRService {
    private let logger = Logger(subsystem: "Salty", category: "App")
    
    var isProcessing = false
    var extractedText = ""
    var error: RecipeOCRError?
    
    func extractText(from image: CGImage) async {
        isProcessing = true
        error = nil
        extractedText = ""
        
        do {
            let text = try await performOCR(on: image)
            extractedText = text
            
            logger.info("Successfully extracted \(text.count) characters from image")
            
        } catch {
            self.error = error as? RecipeOCRError ?? RecipeOCRError.processingFailed
            logger.error("OCR failed: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    
    #if os(iOS)
    func extractTextFromMultiPageScan(_ scan: VNDocumentCameraScan) async {
        isProcessing = true
        error = nil
        extractedText = ""
        
        do {
            var allText: [String] = []
            let pageCount = scan.pageCount
            
            for i in 0..<pageCount {
                let pageImage = scan.imageOfPage(at: i)
                if let cgImage = pageImage.cgImage {
                    let pageText = try await performOCR(on: cgImage)
                    allText.append(pageText)
                    
                    // Add page separator
                    if i < pageCount - 1 {
                        allText.append("\n--- Page \(i + 2) ---\n")
                    }
                }
            }
            
            extractedText = allText.joined(separator: "\n")
            logger.info("Successfully extracted text from \(pageCount) pages")
            
        } catch {
            self.error = error as? RecipeOCRError ?? RecipeOCRError.processingFailed
            logger.error("Multi-page OCR failed: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    #elseif os(macOS)
    func extractTextFromMultiPageScan(_ scan: [CGImage]) async {
        isProcessing = true
        error = nil
        extractedText = ""
        
        do {
            var allText: [String] = []
            let pageCount = scan.count
            
            for (i, cgImage) in scan.enumerated() {
                let pageText = try await performOCR(on: cgImage)
                allText.append(pageText)
                
                // Add page separator
                if i < pageCount - 1 {
                    allText.append("\n--- Page \(i + 2) ---\n")
                }
            }
            
            extractedText = allText.joined(separator: "\n")
            logger.info("Successfully extracted text from \(pageCount) pages")
            
        } catch {
            self.error = error as? RecipeOCRError ?? RecipeOCRError.processingFailed
            logger.error("Multi-page OCR failed: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    #endif
    
    // MARK: - PDF

    /// Extracts recipe text from a PDF (any page count) into one string. Digital PDFs carrying a real
    /// text layer are read directly (accurate, no OCR); image-only / scanned PDFs are rendered page-by-
    /// page and OCR'd. Pages are joined with "--- Page N ---" separators.
    func extractText(fromPDFData data: Data) async {
        isProcessing = true
        error = nil
        extractedText = ""
        defer { isProcessing = false }

        guard let pages = await pageTexts(fromPDFData: data) else { return }
        let joined = Self.joinPages(pages)
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.error = .noTextFound
            return
        }
        extractedText = joined
        logger.info("Extracted text from \(pages.count)-page PDF")
    }

    /// Per-page text for a PDF -- used when splitting one multi-page file into several recipes. Same
    /// digital-text-or-OCR decision as `extractText(fromPDFData:)`, kept one entry per page. Returns []
    /// (and sets `error`) when the PDF can't be opened.
    func extractPageTexts(fromPDFData data: Data) async -> [String] {
        isProcessing = true
        error = nil
        defer { isProcessing = false }
        return await pageTexts(fromPDFData: data) ?? []
    }

    /// Shared core for the two entry points above: one text string per page (embedded text when the PDF
    /// has a real text layer, else per-page OCR), or nil (setting `error`) when the PDF can't be opened.
    private func pageTexts(fromPDFData data: Data) async -> [String]? {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            self.error = .invalidDocument
            logger.error("Could not open PDF for text extraction")
            return nil
        }
        let pageCount = document.pageCount

        // Digital PDF: use the embedded text layer directly.
        let embedded = (0..<pageCount).map { document.page(at: $0)?.string ?? "" }
        if Self.hasMeaningfulText(embedded) {
            logger.info("Read embedded text from \(pageCount)-page PDF")
            return embedded
        }

        // Scanned PDF: render and OCR each page (blank/unreadable pages become "").
        var pages: [String] = []
        for i in 0..<pageCount {
            if let page = document.page(at: i), let image = Self.render(page, scale: 2.0) {
                pages.append((try? await performOCR(on: image)) ?? "")
            } else {
                pages.append("")
            }
        }
        logger.info("OCR-extracted text from \(pageCount)-page scanned PDF")
        return pages
    }

    /// Page count of a PDF (0 if it can't be opened).
    static func pageCount(fromPDFData data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }

    /// Renders the first page of a PDF for preview (e.g. the picked-file thumbnail).
    static func previewImage(fromPDFData data: Data) -> CGImage? {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { return nil }
        return render(page, scale: 2.0)
    }

    /// Renders every page to a CGImage (small, for the split-into-recipes page list).
    static func pageImages(fromPDFData data: Data, scale: CGFloat = 0.5) -> [CGImage] {
        guard let document = PDFDocument(data: data) else { return [] }
        return (0..<document.pageCount).compactMap { index in
            document.page(at: index).flatMap { render($0, scale: scale) }
        }
    }

    /// True when the combined pages contain enough alphanumerics to be a real text layer (vs. the empty
    /// or garbage strings a scanned, image-only PDF returns).
    private static func hasMeaningfulText(_ pages: [String]) -> Bool {
        let letters = pages.joined().unicodeScalars.lazy.filter { CharacterSet.alphanumerics.contains($0) }
        return letters.count >= 20
    }

    /// Joins page texts with the same "--- Page N ---" separators the multi-page scan path uses.
    private static func joinPages(_ pages: [String]) -> String {
        var parts: [String] = []
        for (i, text) in pages.enumerated() {
            parts.append(text)
            if i < pages.count - 1 { parts.append("\n--- Page \(i + 2) ---\n") }
        }
        return parts.joined(separator: "\n")
    }

    /// Rasterizes a PDF page to a CGImage at the given scale (≈72·scale DPI) for OCR / preview.
    private static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            return nil
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private func performOCR(on cgImage: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: RecipeOCRError.processingFailed)
                    return
                }
                
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                let fullText = recognizedStrings.joined(separator: "\n")
                
                if fullText.isEmpty {
                    continuation.resume(throwing: RecipeOCRError.noTextFound)
                } else {
                    continuation.resume(returning: fullText)
                }
            }
            
            // Configure the request for better accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.01 // Adjust as needed
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
} 

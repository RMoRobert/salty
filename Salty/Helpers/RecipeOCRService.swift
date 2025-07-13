//
//  RecipeOCRService.swift
//  Salty
//
//  Created by Robert on 7/13/25.
//

import Vision
import VisionKit
import Foundation
import OSLog

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum RecipeOCRError: Error, LocalizedError {
    case invalidImage
    case noTextFound
    case processingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The provided image is invalid or cannot be processed."
        case .noTextFound:
            return "No text was found in the image."
        case .processingFailed:
            return "Failed to process the image for text recognition."
        }
    }
}

@MainActor
class RecipeOCRService: ObservableObject {
    private let logger = Logger(subsystem: "Salty", category: "App")
    
    @Published var isProcessing = false
    @Published var extractedText = ""
    @Published var error: RecipeOCRError?
    
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
    
    func clearResults() {
        extractedText = ""
        error = nil
    }
} 

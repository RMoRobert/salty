//
//  DirectionTextParser.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import Foundation

/// Utility class for parsing and formatting direction text
struct DirectionTextParser {
    
    /// Parses bulk text into Direction objects
    /// - Parameter text: Raw text input with directions
    /// - Returns: Array of Direction objects with proper heading detection
    static func parseDirections(from text: String) -> [Direction] {
        let lines = text.components(separatedBy: .newlines)
        var directions: [Direction] = []
        
        var i = 0
        while i < lines.count {
            var line = lines[i].trimmingCharacters(in: .whitespaces)
            
            if line.isEmpty {
                // Skip empty lines
                i += 1
                continue
            }
            
            // Check if this line is preceded by two blank lines, making it a heading:
            let isHeadingByDoubleLine = i > 1 && 
                lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty && 
                lines[i - 2].trimmingCharacters(in: .whitespaces).isEmpty
            
            // Check if this line ends with a colon, making it a heading using the alternate format:
            let isHeadingByColon = line.hasSuffix(":")
            if isHeadingByColon {
                // strip colon for cleanliness
                line = String(line.dropLast())
            }
            let isHeading = isHeadingByDoubleLine || isHeadingByColon
            
            // Collect all text until we hit a double line break or another heading
            var directionText = line
            var j = i + 1
            
            // If this line is a heading (ends with colon), don't collect additional text
            if !isHeading {
                while j < lines.count {
                    let nextLine = lines[j].trimmingCharacters(in: .whitespaces)
                    
                    // Check if we've hit a double line break (empty line followed by content)
                    if nextLine.isEmpty {
                        // Look ahead to see if there's content after this empty line
                        var k = j + 1
                        while k < lines.count && lines[k].trimmingCharacters(in: .whitespaces).isEmpty {
                            k += 1
                        }
                        
                        // If we found content after empty line(s), this is a break point
                        if k < lines.count {
                            break
                        }
                        // Otherwise, skip this empty line and continue
                        j += 1
                        continue
                    }
                    
                    // Check if next line is a heading (ends with colon)
                    if nextLine.hasSuffix(":") {
                        break
                    }
                    
                    // Add this line to current direction (with a space separator)
                    directionText += " " + nextLine
                    j += 1
                }
            }
            
            let direction = Direction(
                id: UUID().uuidString,
                isHeading: isHeading,
                text: directionText
            )
            
            directions.append(direction)
            i = j
        }
        
        return directions
    }
    
    /// Formats Direction objects into text for editing
    /// - Parameter directions: Array of Direction objects
    /// - Returns: Formatted text string
    static func formatDirections(_ directions: [Direction]) -> String {
        var lines: [String] = []
        
        for (index, direction) in directions.enumerated() {
            if direction.isHeading == true {
                // Add double blank line before heading (two empty lines)
                lines.append("")
                lines.append("")
                lines.append(direction.text)
            } else {
                // Add single blank line before regular directions (except the first one)
                if index > 0 && !lines.isEmpty {
                    lines.append("")
                }
                lines.append(direction.text)
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Cleans up text by removing list markers and numbered prefixes
    /// - Parameter text: Raw text to clean
    /// - Returns: Cleaned text
    static func cleanUpText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let cleanedLines = lines.map { line in
            var cleanedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Remove common list markers from the beginning
            let markers = ["*", "-", "•", "○", "▪", "▫", "‣", "⁃"]
            for marker in markers {
                if cleanedLine.hasPrefix(marker) {
                    cleanedLine = String(cleanedLine.dropFirst(marker.count))
                    break
                }
            }
            
            // Remove numbered prefixes like "1.", "2)", etc.
            if let range = cleanedLine.range(of: "^\\d+[.)]\\s*", options: .regularExpression) {
                cleanedLine = String(cleanedLine[range.upperBound...])
            }
            
            return cleanedLine.trimmingCharacters(in: .whitespaces)
        }
        return cleanedLines.joined(separator: "\n")
    }
    
    /// Simple parsing for basic use cases (like web extraction)
    /// - Parameter text: Raw text input
    /// - Returns: Array of Direction objects with no heading detection
    static func parseDirectionsSimple(from text: String) -> [Direction] {
        let lines = text.components(separatedBy: .newlines)
        var directions: [Direction] = []
        
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanLine.isEmpty {
                let direction = Direction(
                    id: UUID().uuidString,
                    isHeading: false,
                    text: cleanLine
                )
                directions.append(direction)
            }
        }
        
        return directions
    }
    
    /// Simple parsing with cleanup for web extraction
    /// - Parameter text: Raw text input
    /// - Returns: Array of Direction objects with no heading detection, cleaned up
    static func parseDirectionsSimpleWithCleanup(from text: String) -> [Direction] {
        let cleanedText = cleanUpText(text)
        return parseDirectionsSimple(from: cleanedText)
    }
} 
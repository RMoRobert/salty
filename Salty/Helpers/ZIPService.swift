//
//  ZIPService.swift
//  Salty
//
//  Created by Robert on 7/19/25.
//
// Inspired by: https://medium.com/parable-engineering/how-to-easily-create-zip-files-in-swift-without-third-party-dependencies-a1c36a451ea1

import Foundation

// MARK: - Errors

enum CreateZipError: Swift.Error {
    case urlNotADirectory(URL)
    case failedToCreateZIP(Swift.Error)
    case failedToGetDataFromZipURL
}

// MARK: - FileToZip

enum FileToZip {
    case data(Data, filename: String)
    case existingFile(URL)
    case renamedFile(URL, toFilename: String)
}

extension FileToZip {
    static func text(_ text: String, filename: String) -> FileToZip {
        .data(text.data(using: .utf8) ?? Data(), filename: filename)
    }
}

extension FileToZip {
    func prepareInDirectory(directoryURL: URL) throws {
        switch self {
        case .data(let data, filename: let filename):
            let fileURL = directoryURL.appendingPathComponent(filename)
            try data.write(to: fileURL)
        case .existingFile(let existingFileURL):
            let filename = existingFileURL.lastPathComponent
            let newFileURL = directoryURL.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: existingFileURL, to: newFileURL)
        case .renamedFile(let existingFileURL, toFilename: let filename):
            let newFileURL = directoryURL.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: existingFileURL, to: newFileURL)
        }
    }
}

// MARK: - ZipService

final class ZipService {

    init() { }
    var shouldOverwriteIfNecessary: Bool = false
    
    static func urlIsDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
    
    func createZip(
        zipFinalURL: URL,
        fromDirectory directoryURL: URL
    ) throws -> URL {
        // see URL extension below
        guard ZipService.urlIsDirectory(directoryURL) else {
            throw CreateZipError.urlNotADirectory(directoryURL)
        }
        
        var fileManagerError: Swift.Error?
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: directoryURL,
            options: .forUploading,
            error: &coordinatorError
        ) { zipAccessURL in
            do {
                if shouldOverwriteIfNecessary {
                    try FileManager.default.replaceItemAt(zipFinalURL, withItemAt: zipAccessURL)
                } else {
                    try FileManager.default.moveItem(at: zipAccessURL, to: zipFinalURL)
                }
            } catch {
                fileManagerError = error
            }
        }
        if let error = coordinatorError ?? fileManagerError {
            throw CreateZipError.failedToCreateZIP(error)
        }
        return zipFinalURL
    }

    func createZipAtTmp(
        zipFilename: String,
        zipExtension: String = "zip",
        fromDirectory directoryURL: URL
    ) throws -> URL {
        let finalURL = FileManager.default.temporaryDirectory
            .appending(path: zipFilename)
            .appendingPathExtension(zipExtension)
        return try createZip(
            zipFinalURL: finalURL,
            fromDirectory: directoryURL
        )
    }

    func createZipAtTmp(
        zipFilename: String,
        zipExtension: String = "zip",
        filesToZip: [FileToZip]
    ) throws -> URL {
        let directoryToZipURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: zipFilename)
        try FileManager.default.createDirectory(at: directoryToZipURL, withIntermediateDirectories: true, attributes: [:])
        for fileToZip in filesToZip {
            try fileToZip.prepareInDirectory(directoryURL: directoryToZipURL)
        }
        return try createZipAtTmp(
            zipFilename: zipFilename,
            zipExtension: zipExtension,
            fromDirectory: directoryToZipURL
        )
    }
    
    private func getZipData(zipFileURL: URL) throws -> Data {
        if let data = FileManager.default.contents(atPath: zipFileURL.path) {
            return data
        } else {
            throw CreateZipError.failedToGetDataFromZipURL
        }
    }

    func getZipData(
        zipFilename: String = UUID().uuidString,
        fromDirectory directoryURL: URL
    ) throws -> Data {
        let zipURL = try createZipAtTmp(
            zipFilename: zipFilename,
            fromDirectory: directoryURL
        )
        return try getZipData(zipFileURL: zipURL)
    }
    
    func getZipData(
        zipFilename: String = UUID().uuidString,
        filesToZip: [FileToZip]
    ) throws -> Data {
        let zipURL = try createZipAtTmp(
            zipFilename: zipFilename,
            filesToZip: filesToZip
        )
        return try getZipData(zipFileURL: zipURL)
    }
}

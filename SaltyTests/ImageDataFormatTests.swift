//
//  ImageDataFormatTests.swift
//  SaltyTests
//
//  Pins what the JSON-LD importer relies on: junk (error pages, empty bodies) is rejected and real
//  image containers are not.
//

import Testing
import Foundation
import SaltyCore

struct ImageDataFormatTests {

    // MARK: - Real containers are recognised

    /// Header bytes only: `detect` reads a signature, it doesn't decode, and the importer's job is to
    /// tell an image apart from an error page.
    @Test("each supported container is identified from its signature", arguments: [
        (ImageDataFormat.jpeg, [0xFF, 0xD8, 0xFF, 0xE0] as [UInt8]),
        (.png, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        (.gif, Array("GIF89a".utf8)),
        (.gif, Array("GIF87a".utf8)),
        (.tiff, [0x49, 0x49, 0x2A, 0x00]),
        (.tiff, [0x4D, 0x4D, 0x00, 0x2A]),
    ])
    func detectsContainer(expected: ImageDataFormat, header: [UInt8]) {
        #expect(ImageDataFormat.detect(Data(header + Array(repeating: 0, count: 32))) == expected)
    }

    @Test("a RIFF/WEBP container is identified by its brand, not just the RIFF tag")
    func detectsWebP() {
        var bytes = Array("RIFF".utf8)
        bytes += [0x20, 0x00, 0x00, 0x00]   // chunk size
        bytes += Array("WEBP".utf8)
        #expect(ImageDataFormat.detect(Data(bytes)) == .webp)

        // Same container, different payload: a RIFF WAVE file is not an image.
        var wave = Array("RIFF".utf8)
        wave += [0x20, 0x00, 0x00, 0x00]
        wave += Array("WAVE".utf8)
        #expect(ImageDataFormat.detect(Data(wave)) == nil)
    }

    @Test("ISO base-media files are matched on brand, so HEIC is an image and MP4 is not")
    func distinguishesHeicFromVideo() {
        func isoFile(brand: String) -> Data {
            var bytes: [UInt8] = [0x00, 0x00, 0x00, 0x18]   // box length
            bytes += Array("ftyp".utf8)
            bytes += Array(brand.utf8)
            return Data(bytes + Array(repeating: 0, count: 16))
        }
        #expect(ImageDataFormat.detect(isoFile(brand: "heic")) == .heic)
        #expect(ImageDataFormat.detect(isoFile(brand: "mif1")) == .heic)
        #expect(ImageDataFormat.detect(isoFile(brand: "avif")) == .heic)
        // An MP4 shares the "ftyp" box; only the brand tells them apart.
        #expect(ImageDataFormat.detect(isoFile(brand: "isom")) == nil)
        #expect(ImageDataFormat.detect(isoFile(brand: "mp42")) == nil)
    }

    // MARK: - What the importer actually has to reject

    @Test("the payloads a recipe image URL really returns when it fails are rejected", arguments: [
        "<!DOCTYPE html><html><head><title>404 Not Found</title></head><body>…</body></html>",
        "<html><body>Please sign in to continue</body></html>",
        #"{"error":"forbidden"}"#,
        "",
        "not an image at all",
    ])
    func rejectsNonImagePayloads(body: String) {
        #expect(ImageDataFormat.isRecognisedImage(Data(body.utf8)) == false)
    }

    @Test("a body too short to carry any signature is rejected rather than trapping")
    func rejectsTruncatedData() {
        for length in 0...8 {
            let data = Data(Array(repeating: UInt8(0xFF), count: length))
            _ = ImageDataFormat.isRecognisedImage(data)   // must not trap
        }
        #expect(ImageDataFormat.detect(Data([0xFF, 0xD8])) == nil)   // JPEG needs three bytes
    }

    /// `Data` taken from the middle of a buffer has a non-zero `startIndex`; indexing it from 0 traps.
    @Test("a Data slice with a non-zero start index is read correctly")
    func handlesSlicedData() {
        let padded = Data(Array(repeating: UInt8(0x00), count: 64) + [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let slice = padded[64...]
        #expect(slice.startIndex != 0)
        #expect(ImageDataFormat.detect(slice) == .png)
    }

    @Test("file extensions match what the image folder already writes")
    func fileExtensions() {
        #expect(ImageDataFormat.jpeg.fileExtension == "jpg")
        #expect(ImageDataFormat.png.fileExtension == "png")
        #expect(ImageDataFormat.heic.fileExtension == "heic")
    }
}

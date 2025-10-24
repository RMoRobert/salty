//
//  ImportError.swift
//  Salty
//
//  Created by Robert on 8/16/25.
//

import Foundation

enum ImportError: LocalizedError {
    case noDataFound
    case decodingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .noDataFound:
            return "No data found in the file"
        case .decodingFailed(let error):
            return "Could not decode recipe file: \(error.localizedDescription)"
        }
    }
}

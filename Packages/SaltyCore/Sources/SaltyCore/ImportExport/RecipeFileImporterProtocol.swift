//
//  ImporterProtocol.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import Foundation
//import SWXMLHash

public protocol RecipeFileImporterProtocol {
    
}

public extension RecipeFileImporterProtocol {
    public static func getDataFromFile(_ fileUrl: URL) -> Data? {
        guard let data = try? Data(contentsOf: fileUrl) else {
            return nil
        }
        return data
    }
       
//    static func getXMLParserForFile(_ fileUrl: URL) -> XMLParser? {
//        guard let data = getDataFromFile(fileUrl) else {
//            return nil
//        }
//        let xmlParser = XMLParser(data: data)
//        return xmlParser
//    }
    
    
}

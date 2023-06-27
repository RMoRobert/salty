//
//  Note.swift
//  Salty
//
//  Created by Robert on 4/19/23.
//

import Foundation
import RealmSwift

final class Note: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var name = ""
    @Persisted var text = ""
}

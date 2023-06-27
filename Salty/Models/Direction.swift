//
//  Direction.swift
//  Salty
//
//  Created by Robert on 4/19/23.
//

import Foundation
import RealmSwift

final class Direction: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var stepName = ""
    @Persisted var text = ""
}

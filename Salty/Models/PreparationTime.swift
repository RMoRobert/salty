//
//  PreparationTime.swift
//  Salty
//
//  Created by Robert on 4/19/23.
//

import Foundation
import RealmSwift


import RealmSwift

final class PreparationTime: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var name = ""
    @Persisted var timeString = ""
}

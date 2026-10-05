//
//  LibraryClassifier+Names.swift
//  Salty
//
//  What the app calls each kind of classifier. SaltyCore defines the kinds; each client names them.
//

import SaltyCore

extension LibraryClassifier {
    /// "Category", "Course", "Tag".
    var singularName: String {
        switch self {
        case .category: "Category"
        case .course: "Course"
        case .tag: "Tag"
        }
    }

    /// "Categories", "Courses", "Tags".
    var pluralName: String {
        switch self {
        case .category: "Categories"
        case .course: "Courses"
        case .tag: "Tags"
        }
    }
}

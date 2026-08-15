//
//  SaltyCoreTypeAliases.swift
//  Salty
//
//  Disambiguates SaltyCore type names that collide with something the SDK already puts in scope.
//
//  `Category` is the only one so far, and it collides with the Objective-C runtime's
//  `typedef struct objc_category *Category` (objc/runtime.h), which arrives transitively via
//  Foundation/AppKit/UIKit. While the model lived in the app module this was invisible: unqualified
//  lookup prefers the current module, so our `Category` simply won. Imported from SaltyCore it became
//  just another candidate, and `Category` turned ambiguous -- but only in the files where the ObjC
//  header is actually visible, which is why it surfaced in one view model rather than everywhere.
//
//  Re-declaring the name in this module restores that original precedence, so the ~24 places that say
//  `Category` keep working untouched, and a use that means the ObjC type can still say `ObjectiveC.Category`.
//
//  Note for a future tvOS (or any other) client of SaltyCore: it will hit the same collision and needs
//  its own alias, or should qualify as `SaltyCore.Category`.
//

import SaltyCore

typealias Category = SaltyCore.Category

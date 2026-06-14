//
//  MainView.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import SwiftUI

struct MainView: View {
    // Own the root view model here (created once) rather than re-instantiating it inside `body`
    // on every render. `isNewLaunch` is set via the initializer so it's applied to the persisted
    // instance, not a throwaway one.
    @State private var viewModel = RecipeNavigationSplitViewModel(isNewLaunch: true)

    var body: some View {
        RecipeNavigationSplitView(viewModel: viewModel)
    }
}

#Preview {
    MainView()
}

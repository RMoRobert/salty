//
//  MainView.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import SwiftUI

struct MainView: View {
    var body: some View {
        let viewModel = RecipeNavigationSplitViewModel()
        let _ = viewModel.isNewLaunch = true
        RecipeNavigationSplitView(viewModel: viewModel)
    }
}

#Preview {
    MainView()
}

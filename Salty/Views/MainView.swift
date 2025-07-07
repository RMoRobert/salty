//
//  MainView.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import SwiftUI

struct MainView: View {
    var body: some View {
        RecipeNavigationSplitView(viewModel: RecipeNavigationSplitViewModel())
    }
}

#Preview {
    MainView()
}

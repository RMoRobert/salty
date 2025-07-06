//
//  SettingsView.swift
//  Salty
//
//  Created by Robert on 7/6/25.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsView()
            }
//            Tab("Advanced", systemImage: "star") {
//                AdvancedSettingsView()
//            }
        }
        .scenePadding()
        .frame(maxWidth: 350, minHeight: 100)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("webPreviews") private var useWebRecipeDetailView = true
    
    var body: some View {
        Form {
            Toggle("Use web-based recipe detail view (instead of native UI-based view)", isOn: $useWebRecipeDetailView)
        }
    }
}


#Preview {
    SettingsView()
}

//
//  CreateRecipeFromWebView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import SwiftUI

struct CreateRecipeFromWebView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Create Recipe from Web")
                    .font(.title)
                    .padding()
                
                Text("This feature is coming soon!")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationTitle("Create from Web")
            //.navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CreateRecipeFromWebView()
}

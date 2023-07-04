//
//  RatingView.swift
//  Salty
//
//  Created by Robert on 7/3/23.
//

import Foundation
import SwiftUI

/// View-only star rating for recipes (0-5 stars)
//struct RatingView: View {
//    @State var rating: Recipe.Rating
//
//    var body: some View {
//        Gauge(value: Double(rating.rawValue), in: Double(0)...Double(5)) {
//            Label("Rating", systemImage: "star.bubble")
//        } currentValueLabel: {
//            HStack {
//                Text(rating.rawValue.formatted())
//                    .font(.callout)
//                Image(systemName: "star.fill")
//                    .font(.callout)
//            }
//        } minimumValueLabel: {
//            Text("1")
//                .foregroundColor(.red)
//        } maximumValueLabel: {
//            Text("5")
//                .foregroundColor(.green)
//        }
//        .gaugeStyle(.accessoryCircular)
//        .tint(Gradient(colors: [.red, .yellow, .green]))
//            .accessibilityLabel("Rating: \(rating.rawValue) star(s)")
//    }
//}


struct RatingView: View {
    @State var rating: Recipe.Rating
    
    var body: some View {
        HStack {
            ForEach(1..<6) { val in
                if rating.rawValue > val {
                    Image(systemName: "star.fill")
                        .symbolRenderingMode(.multicolor)
                }
                else {
                    Image(systemName: "star")
                        .foregroundStyle(.gray)
                }
            }
        }
        .accessibilityLabel("Rating: \(rating.rawValue) star(s)")
    }
}



struct RatingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            let rawRating = 3
            RatingView(rating: Recipe.Rating.init(rawValue: rawRating)!)
        }
    }
}

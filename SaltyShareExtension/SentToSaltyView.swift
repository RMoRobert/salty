//
//  SentToSaltyView.swift
//  SaltyShareExtension
//
//  What the iOS share sheet shows after the page has been handed over (or couldn't be).
//

#if os(iOS)
import SwiftUI

struct SentToSaltyView: View {
    enum Outcome {
        /// The page is in the inbox; the app opens it next time it is in front.
        case sent(URL)
        /// Nothing shared was a web address.
        case notAWebPage
    }

    let outcome: Outcome
    let done: () -> Void

    var body: some View {
        VStack {
            Spacer()
            switch outcome {
            case .sent(let page):
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Sent to Salty")
                    .font(.title2)
                    .bold()
                Text(page.host() ?? page.absoluteString)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Open Salty to import this recipe.")
            case .notAWebPage:
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("That Isn't a Web Page")
                    .font(.title2)
                    .bold()
                Text("Salty can import recipes from web pages only.")
            }
            Spacer()
            Button("Done", action: done)
                .buttonStyle(.borderedProminent)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Sent") {
    SentToSaltyView(outcome: .sent(URL(string: "https://www.example.com/recipes/pie")!)) { }
}

#Preview("Not a web page") {
    SentToSaltyView(outcome: .notAWebPage) { }
}
#endif

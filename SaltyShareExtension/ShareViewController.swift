//
//  ShareViewController.swift
//  SaltyShareExtension
//
//  The "Salty" item in the share sheet (iOS) and the Share menu (macOS): sends the page being viewed
//  to Web Import. The extension's principal class; one per platform, both named for Info.plist.
//
//  Only an http(s) page can be imported, and only its address travels: the page is loaded again in
//  Salty's own browser and scanned there, exactly as a `salty://import` link does, so there is one
//  import path to keep working. (That means a page behind a login shows its login wall in Salty; see
//  FEATURE_PLANS "Browser hand-off" for the in-extension import that would avoid it.)
//

import OSLog

/// `log stream --predicate 'subsystem == "Salty"'` shows these alongside the app's own lines.
private let logger = Logger(subsystem: "Salty", category: "ShareExtension")

#if os(iOS)
import SwiftUI
import UIKit

/// iOS: a share extension isn't allowed to open its app, so the page goes into `ImportInbox` for the
/// app to open when it next comes to the front, and the sheet says so.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 360, height: 280)
        Task { await handOff() }
    }

    private func handOff() async {
        let outcome: SentToSaltyView.Outcome
        if let page = await SharedPage.url(in: extensionContext),
           case .importFromWeb(let webPage)? = SaltyURL.importLink(for: page) {
            ImportInbox.append(webPage)
            logger.info("Sent a page to the inbox: \(webPage.host() ?? "?", privacy: .public)")
            outcome = .sent(webPage)
        } else {
            logger.info("Nothing shared was a web page")
            outcome = .notAWebPage
        }
        show(outcome)
    }

    private func show(_ outcome: SentToSaltyView.Outcome) {
        let host = UIHostingController(rootView: SentToSaltyView(outcome: outcome) { [weak self] in
            self?.finish()
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        // A success needs no acknowledging: the sheet goes away on its own, as a "Saved" banner does.
        if case .sent = outcome {
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                finish()
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

#elseif os(macOS)
import AppKit

/// macOS: opens the `salty://import` link straight away -- the app comes forward with Web Import on
/// the page -- so there is nothing to show.
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await handOff() }
    }

    private func handOff() async {
        guard let page = await SharedPage.url(in: extensionContext),
              let link = SaltyURL.importLink(for: page) else {
            logger.info("Nothing shared was a web page")
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            return
        }
        logger.info("Opening a page in Salty: \(page.host() ?? "?", privacy: .public)")
        NSWorkspace.shared.open(link.url)
        extensionContext?.completeRequest(returningItems: nil)
    }
}
#endif

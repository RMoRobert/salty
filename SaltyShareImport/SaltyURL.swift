//
//  SaltyURL.swift
//  Salty
//
//  The `salty://` links the app opens, parsed into what they ask for -- and built back, so every
//  place that hands one out (the Shortcuts actions, Copy Private Link) spells it the same way.
//
//  The host is the verb or resource; the rest is its argument:
//
//      salty://import?url=<web address>    open Web Import on that page and scan it for a recipe
//      salty://recipe/<id>                 show that recipe
//
//  The `salty:///import` spelling other apps use (Things, OmniFocus: no host, the verb is the first
//  path component) is read the same way, so a link typed from their example works too; links the
//  app writes use the two-slash form. The OS only ever looks at `salty:`.
//
//  The web address is percent-encoded as any query value is; an unencoded one still parses as long
//  as it has no `&` or `#` of its own, which is most recipe pages. A link is an attack surface, so
//  nothing here is trusted beyond its shape: an import takes only http(s) addresses, and a recipe
//  link is only ever an id to look up.
//

import Foundation

enum SaltyURL: Equatable, Sendable {
    static let scheme = "salty"

    /// `salty://import?url=…`: open Web Import on this page.
    case importFromWeb(URL)
    /// `salty://recipe/<id>`: show this recipe.
    case recipe(id: String)

    /// The request `url` makes, or nil when it isn't a well-formed `salty://` link.
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // The request is the host, or with no host (`salty:///…`) the first path component; whatever
        // is left of the path is its argument.
        var arguments = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let request: String
        if let host = components.host, !host.isEmpty {
            request = host.lowercased()
        } else if !arguments.isEmpty {
            request = arguments.removeFirst().lowercased()
        } else {
            return nil
        }

        switch request {
        case "import":
            guard let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
                  let page = Self.webAddress(value) else {
                return nil
            }
            self = .importFromWeb(page)

        case "recipe":
            // Exactly one argument, the id: "/<id>" and nothing more.
            guard arguments.count == 1, let id = arguments.first, !id.isEmpty else { return nil }
            self = .recipe(id: id)

        default:
            return nil
        }
    }

    /// The import link for `page`, or nil when it isn't a web page -- the Shortcuts action can be
    /// handed any URL at all.
    static func importLink(for page: URL) -> SaltyURL? {
        webAddress(page.absoluteString).map { .importFromWeb($0) }
    }

    /// The link for this request, as `init` reads it back.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .importFromWeb(let page):
            components.host = "import"
            components.queryItems = [URLQueryItem(name: "url", value: page.absoluteString)]
        case .recipe(let id):
            components.host = "recipe"
            components.path = "/" + id
        }
        // Scheme and host are fixed strings and the arguments are percent-encoded by URLComponents,
        // so this can only fail for an id URLComponents refuses in a path, which recipe ids never are.
        return components.url ?? URL(string: "\(Self.scheme)://")!
    }

    /// The web page an import link names: an http(s) address, with `https://` assumed when the
    /// scheme was left off (as the importer's address bar assumes it). Anything else is refused.
    private static func webAddress(_ value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var url = URL(string: text) else { return nil }
        if url.scheme == nil {
            // No scheme at all is fine...
            guard let withScheme = URL(string: "https://" + text) else { return nil }
            url = withScheme
        }
        // ...some other scheme (file:, javascript:) is not.
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty else {
            return nil
        }
        return url
    }
}

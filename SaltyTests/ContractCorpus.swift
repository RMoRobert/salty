//
//  ContractCorpus.swift
//  SaltyTests
//
//  Loader for the shared conformance corpus (`salty-contract/corpus`). The SaltyKMP core runs the same
//  cases through its own runner; see salty-contract/runners/README.md.
//

import Foundation

/// One case from the corpus: an input, an expected output, and the id of the rule in `SPEC.md` it
/// exists to pin.
///
/// `input` and `expect` stay as untyped JSON because their shape depends on `op` — a string here, an
/// object there, a list somewhere else. Only the dispatcher in `ContractCorpusTests` knows which.
struct CorpusCase: Sendable, CustomStringConvertible {
    let suite: String
    let id: String
    let rule: String
    let caseDescription: String
    let op: String
    let input: JSONValue
    let expect: JSONValue

    /// Platforms known to FAIL this case, keyed `swift` / `kmp` / `dotnet`, with the reason.
    /// A platform named here waives the case — see `SPEC.md` §7.
    let knownDivergence: [String: String]

    /// Platforms the case does not apply to, because the rule permits more than one implementation
    /// and this client chose another. Not a waiver: nothing is wrong.
    let notApplicable: [String: String]

    var description: String { "\(suite)/\(id)" }

    /// What a failure message leads with, so a red test names its own rule and rationale.
    var because: String { "\(suite)/\(id) (\(rule)) \(caseDescription)" }
}

/// A minimal untyped JSON tree. `JSONSerialization` would do, but decoding into an enum keeps the
/// accessors total and the call sites free of `as?` chains.
indirect enum JSONValue: Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var intValue: Int? { if case .number(let d) = self { return Int(d) }; return nil }
    var int64Value: Int64? { if case .number(let d) = self { return Int64(d) }; return nil }
    var arrayValue: [JSONValue] { if case .array(let a) = self { return a }; return [] }
    var isNull: Bool { if case .null = self { return true }; return false }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    static func from(_ any: Any) -> JSONValue {
        switch any {
        case is NSNull: return .null
        case let n as NSNumber:
            // NSNumber erases Bool and numeric alike; the ObjC type encoding is the only way back.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let s as String: return .string(s)
        case let a as [Any]: return .array(a.map(JSONValue.from))
        case let o as [String: Any]: return .object(o.mapValues(JSONValue.from))
        default: return .null
        }
    }
}

enum CorpusLoader {

    /// Every case in every suite, in file then declaration order.
    ///
    /// A missing or empty corpus throws rather than yielding an empty list: a suite that quietly
    /// asserts nothing is worse than one that is red.
    static func load() throws -> [CorpusCase] {
        let directory = try locate()
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !files.isEmpty else {
            throw CorpusError.message("No corpus files under '\(directory.path)'.")
        }

        var cases: [CorpusCase] = []
        for file in files {
            let root = JSONValue.from(try JSONSerialization.jsonObject(with: try Data(contentsOf: file)))
            let suite = root["suite"]?.stringValue ?? file.deletingPathExtension().lastPathComponent

            for raw in root["cases"]?.arrayValue ?? [] {
                guard let id = raw["id"]?.stringValue, let op = raw["op"]?.stringValue else {
                    throw CorpusError.message("A case in \(file.lastPathComponent) is missing `id` or `op`.")
                }
                cases.append(CorpusCase(
                    suite: suite,
                    id: id,
                    rule: raw["rule"]?.stringValue ?? "",
                    caseDescription: raw["description"]?.stringValue ?? "",
                    op: op,
                    input: raw["input"] ?? .null,
                    expect: raw["expect"] ?? .null,
                    knownDivergence: stringMap(raw["known_divergence"]),
                    notApplicable: stringMap(raw["not_applicable"])
                ))
            }
        }

        let duplicates = Dictionary(grouping: cases, by: \.id).filter { $0.value.count > 1 }.keys
        guard duplicates.isEmpty else {
            throw CorpusError.message("Duplicate case ids: \(duplicates.sorted().joined(separator: ", "))")
        }

        return cases
    }

    private static func stringMap(_ value: JSONValue?) -> [String: String] {
        guard case .object(let o)? = value else { return [:] }
        return o.compactMapValues(\.stringValue)
    }

    /// Finds `salty-contract/corpus`.
    ///
    /// The contract is its own repo, checked out beside this one, so there is no path to it from inside
    /// this one. In order: the `SALTY_CORPUS_DIR` environment variable; a `.salty-contract-path` file at
    /// the repo root (gitignored, one line, the path to the corpus); then a walk up from THIS SOURCE
    /// FILE's location looking for `salty-contract/corpus`, checking each ancestor and each ancestor's
    /// immediate children — the last of which is what finds the sibling checkout, and is how this
    /// resolves in an ordinary working copy.
    ///
    /// The first two are escape hatches for a layout the walk does not anticipate. The pointer file was
    /// how this resolved while the contract was a subdirectory of Salty.NET, out of reach of any walk;
    /// nothing writes one now.
    ///
    /// `#filePath` rather than the bundle, because a macOS unit-test bundle's resources are copied at
    /// build time and Xcode schemes here are autocreated into gitignored `xcuserdata` — so neither a
    /// resource copy phase nor a scheme environment variable is a durable place to put this.
    private static func locate() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["SALTY_CORPUS_DIR"], !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            guard isDirectory(url) else {
                throw CorpusError.message("SALTY_CORPUS_DIR is set to '\(configured)', which is not a directory.")
            }
            return url
        }

        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let pointer = directory.appendingPathComponent(".salty-contract-path")
            if let text = try? String(contentsOf: pointer, encoding: .utf8) {
                let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = URL(fileURLWithPath: path)
                if isDirectory(url) { return url }
            }

            let direct = directory.appendingPathComponent("salty-contract/corpus")
            if isDirectory(direct) { return direct }

            let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for child in children where isDirectory(child.appendingPathComponent("salty-contract/corpus")) {
                return child.appendingPathComponent("salty-contract/corpus")
            }

            directory = directory.deletingLastPathComponent()
        }

        throw CorpusError.message("""
            Could not find salty-contract/corpus.
            Put its path in a `.salty-contract-path` file at the repo root (gitignored), \
            or set SALTY_CORPUS_DIR in the environment.
            """)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

enum CorpusError: Error, CustomStringConvertible {
    case message(String)
    var description: String { if case .message(let m) = self { return m }; return "" }
}

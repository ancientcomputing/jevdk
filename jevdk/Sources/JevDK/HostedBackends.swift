import AppKit
import Foundation
import LocalLMLabSDKCore
import LocalLMLabSDKRemote

/// The hosted Jev backends JevDK offers, each an SDK `JevDecisionProvider` registered in the
/// lab under its own decision scheme.
enum HostedBackend: String, CaseIterable, Identifiable, Sendable {
    case featherlessDemo, featherless, openRouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .featherlessDemo: "Featherless demo"
        case .featherless: "Featherless"
        case .openRouter: "OpenRouter · TypeSafe"
        }
    }

    var blurb: String {
        switch self {
        case .featherlessDemo: "Free, no key · 2k-token context, a few requests per second · token-scored like Local"
        case .featherless: "featherless.ai key · token-scored like Local"
        case .openRouter: "OpenRouter key · TypeSafe's decision-trained Jev"
        }
    }

    var needsKey: Bool { self != .featherlessDemo }

    /// Who receives the text a run sends, for the consent question (AIDataConsent).
    var dataRecipient: String {
        switch self {
        case .featherlessDemo: "Featherless's free demo service (featherless.ai)"
        case .featherless: "Featherless (featherless.ai)"
        case .openRouter: "OpenRouter (openrouter.ai), which passes it to TypeSafe's Jev model"
        }
    }

    /// Environment variable checked when no key is saved in the Keychain (CI, headless runs).
    var keyVariable: String? {
        switch self {
        case .featherlessDemo: nil
        case .featherless: "FEATHERLESS_API_KEY"
        case .openRouter: "OPENROUTER_API_KEY"
        }
    }

    var defaultModel: String {
        switch self {
        case .featherlessDemo, .featherless: "featherless-ai/Qwen3.8-27B-classifier"
        case .openRouter: "typesafe/jev-1.13"
        }
    }

    /// The SDK config, with a scheme of its own so the demo and the keyed Featherless endpoint
    /// can both be registered in one lab.
    func config(key: String?) -> JevProviderConfig {
        var c: JevProviderConfig
        switch self {
        case .featherlessDemo: c = .featherlessDemo()
        case .featherless: c = .featherless(key: key ?? "")
        case .openRouter: c = .openRouter(key: key ?? "")
        }
        c.scheme = rawValue.lowercased()
        return c
    }

    var suggestedModels: [String] { config(key: nil).models }

    /// The free demo is rate-limited; space batch inputs out when it's on.
    var minInterval: Duration { self == .featherlessDemo ? .milliseconds(600) : .zero }

    /// The demo publishes a model list; the others don't have a Jev-specific one.
    var modelsURL: URL? {
        self == .featherlessDemo ? URL(string: "https://simple-jev-demo-api.featherless.ai/v1/models") : nil
    }

    func listModels() async -> [String] {
        guard let url = modelsURL,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]]
        else { return suggestedModels }
        return list.compactMap { $0["id"] as? String }
    }

    func modelID(_ model: String) -> ModelID? { ModelID(scheme: rawValue.lowercased(), rest: model) }

    func label(model: String) -> String {
        "\(displayName) · \(model.split(separator: "/").last.map(String.init) ?? model)"
    }
}

/// The API key for a hosted backend: the one saved in the Keychain from **Backends**, else the
/// environment variable (for CI and headless runs). Never printed. There is no key file: a key
/// in a file next to the code is too easy to commit or share.
enum APIKeys {
    static func key(for backend: HostedBackend) -> String? {
        if let k = Keychain.get(account(backend)), !k.isEmpty { return k }
        guard let name = backend.keyVariable, let v = ProcessInfo.processInfo.environment[name], !v.isEmpty else { return nil }
        return v
    }

    static func account(_ backend: HostedBackend) -> String { "key.\(backend.rawValue)" }
}

/// Asks before a hosted backend is turned on, in the Mac App Store build (App Review guideline
/// 5.1.2(i): name the AI service and what it receives, and get permission first). Asked every time
/// one is turned on, so turning it off is how to withdraw. Other builds don't ask: the Backends
/// sheet already says what hosted backends receive.
@MainActor
enum AIDataConsent {
    static func ask(_ backend: HostedBackend) -> Bool {
        #if MAS_BUILD
        let alert = NSAlert()
        alert.messageText = "Send your text to \(backend.displayName)?"
        alert.informativeText = "While \(backend.displayName) is on, every input you run and your questions "
            + "(with their instructions and options) are sent to \(backend.dataRecipient) to be answered. "
            + "Their terms and privacy policy apply. The Local backend keeps everything on this Mac.\n\n"
            + "Turn the backend off in Backends to stop sending."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
        #else
        true
        #endif
    }
}

import Foundation
import VaakyaCore

/// OpenAI-compatible chat completions client for lens / Ask inference.
/// Network use is only reached when the caller has already obtained egress consent
/// for remote runners. Local runner must use loopback URLs.
actor OpenAILensClient {
    enum Mode: Sendable {
        case local
        case remote
    }

    var baseURL: String
    var apiKey: String
    var model: String
    var mode: Mode
    var session: URLSession

    init(baseURL: String, apiKey: String, model: String, mode: Mode,
         session: URLSession? = nil) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.model = model
        self.mode = mode
        if let session {
            self.session = session
        } else {
            switch mode {
            case .local:
                // Do not follow redirects off loopback.
                let config = URLSessionConfiguration.ephemeral
                config.httpShouldSetCookies = false
                config.timeoutIntervalForRequest = 600
                self.session = URLSession(
                    configuration: config,
                    delegate: LocalLoopbackRedirectDelegate(),
                    delegateQueue: nil)
            case .remote:
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 600
                self.session = URLSession(
                    configuration: config,
                    delegate: RemoteHTTPSRedirectDelegate(),
                    delegateQueue: nil)
            }
        }
    }

    struct ChatRequest: Encodable {
        let model: String
        let messages: [LensChatMessage]
        let temperature: Double
    }

    struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
        let model: String?
    }

    func complete(messages: [LensChatMessage]) async throws -> (content: String, model: String) {
        switch mode {
        case .local:
            guard LocalEndpointPolicy.isAllowedLocalBaseURL(baseURL) else {
                throw OpenAILensError.invalidURL("Local runner requires loopback URL, got: \(baseURL)")
            }
        case .remote:
            guard LocalEndpointPolicy.isAllowedRemoteBaseURL(baseURL) else {
                throw OpenAILensError.invalidURL("Remote runner requires https:// non-loopback URL, got: \(baseURL)")
            }
            guard !apiKey.isEmpty else { throw OpenAILensError.missingAPIKey }
        }

        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw OpenAILensError.invalidURL(baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if mode == .remote || !apiKey.isEmpty {
            // Local typically has no key; only send Authorization when present.
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        request.timeoutInterval = 600
        let body = ChatRequest(model: model, messages: messages, temperature: 0.2)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAILensError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw OpenAILensError.httpStatus(http.statusCode, snippet.prefix(400).description)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw OpenAILensError.emptyContent
        }
        return (content, decoded.model ?? model)
    }
}

/// Rejects HTTP redirects that leave the loopback host or use disallowed schemes.
final class LocalLoopbackRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              comps.user == nil, comps.password == nil,
              LocalEndpointPolicy.isLoopbackHost(comps.host) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

/// Rejects redirects that leave the original HTTPS host (same-origin only).
final class RemoteHTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let original = task.originalRequest?.url,
              let newURL = request.url,
              let o = URLComponents(url: original, resolvingAgainstBaseURL: false),
              let n = URLComponents(url: newURL, resolvingAgainstBaseURL: false),
              o.scheme?.lowercased() == "https",
              n.scheme?.lowercased() == "https",
              n.user == nil, n.password == nil,
              let oHost = o.host?.lowercased(),
              let nHost = n.host?.lowercased(),
              oHost == nHost,
              !LocalEndpointPolicy.isLoopbackHost(nHost) else {
            completionHandler(nil)
            return
        }
        let oPort = o.port ?? 443
        let nPort = n.port ?? 443
        guard oPort == nPort else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum OpenAILensError: LocalizedError {
    case missingAPIKey
    case invalidURL(String)
    case badResponse
    case httpStatus(Int, String)
    case emptyContent
    case egressNotAllowed
    case jobNotCompleted
    case emptyTranscript
    case runnerMisconfigured(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API key missing. Add it in Settings → Lenses for remote runners."
        case .invalidURL(let u): return "Invalid API base URL: \(u)"
        case .badResponse: return "Invalid response from AI API."
        case .httpStatus(let code, let body): return "AI API HTTP \(code): \(body)"
        case .emptyContent: return "AI API returned empty content."
        case .egressNotAllowed:
            return "Text egress is off. Enable AI text egress in Settings and confirm when prompted for Codex/Remote."
        case .jobNotCompleted: return "Transcript must be completed before running a lens."
        case .emptyTranscript: return "No transcript turns to analyze."
        case .runnerMisconfigured(let msg): return msg
        }
    }
}

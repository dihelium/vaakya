import Foundation

/// URL policy for Local (B0 loopback) vs Remote (B1 HTTPS) OpenAI-compatible runners.
public enum LocalEndpointPolicy {
    public static func isAllowedLocalBaseURL(_ base: String) -> Bool {
        guard let comps = URLComponents(string: normalize(base)) else { return false }
        guard let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard comps.user == nil, comps.password == nil else { return false }
        return isLoopbackHost(comps.host)
    }

    public static func isAllowedRemoteBaseURL(_ base: String) -> Bool {
        guard let comps = URLComponents(string: normalize(base)) else { return false }
        guard comps.scheme?.lowercased() == "https" else { return false }
        guard comps.user == nil, comps.password == nil else { return false }
        guard let host = comps.host, !host.isEmpty else { return false }
        // Remote must not claim to be local (use Local runner for loopback).
        if isLoopbackHost(host) { return false }
        return true
    }

    public static func isLoopbackHost(_ host: String?) -> Bool {
        guard var host = host?.lowercased() else { return false }
        // URLComponents may leave brackets on IPv6 literals.
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private static func normalize(_ base: String) -> String {
        base.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

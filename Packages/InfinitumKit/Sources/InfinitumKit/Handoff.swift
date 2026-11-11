import Foundation

/// Hands the native Cumulus ID session to the product web app, so people sign in once.
public enum Handoff {
    /// A document-start script for the main frame. On the product's own hosts it puts the session
    /// where the shared Cumulus ID button looks (`sessionStorage["cumulus-id:<client>"]`).
    public static func sessionScript(product: ProductConfig, session: CumulusSession) -> String {
        let hosts = json(product.appHosts)
        let key = json(product.storageKey)
        let value = json(session.webValue())
        return """
        (function () {
          var hosts = \(hosts);
          if (hosts.indexOf(location.host.toLowerCase()) < 0) return;
          try { sessionStorage.setItem(\(key), JSON.stringify(\(value))); } catch (e) {}
        })();
        """
    }

    /// The first URL to load: `home`, plus `#cid_handoff=` for web apps that read it.
    public static func startURL(product: ProductConfig, home: URL, session: CumulusSession) -> URL {
        guard product.handoffFragment,
              let data = try? JSONSerialization.data(withJSONObject: session.webValue()) else { return home }
        var c = URLComponents(url: home, resolvingAgainstBaseURL: false)!
        if c.path.isEmpty { c.path = "/" }
        c.fragment = "cid_handoff=" + Base64URL.encode(data)
        return c.url ?? home
    }

    /// JSON text for a string, array or object, safe to paste into a script.
    static func json(_ value: Any) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        // "</script>" and line separators cannot end or break the script.
        return text
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}

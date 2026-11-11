import Foundation
@testable import InfinitumKit
import XCTest

final class InfinitumKitTests: XCTestCase {
    let scalvs = ProductConfig(
        id: "scalvs", name: "SCALVS.ai", tagline: "t", clientId: "scalvs",
        home: URL(string: "https://scalvs.app")!, mirrors: [URL(string: "https://ru.scalvs.app")!],
        issuers: [URL(string: "https://id.cumuluscloud.app")!, URL(string: "https://ru.id.cumuluscloud.app")!],
        analytics: true
    )

    func testPKCEMatchesRFC7636AppendixB() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testRandomVerifierIsLongEnough() {
        let v = PKCE().verifier
        XCTAssertGreaterThanOrEqual(v.count, 43)
        XCTAssertNil(v.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testAuthorizeURLEmbeddedUsesOriginRoot() throws {
        let cid = CumulusID(product: scalvs)
        let req = cid.authorizeRequest(issuer: scalvs.issuers[0], home: URL(string: "https://scalvs.app/some/page?x=1")!, create: true, pkce: PKCE(verifier: "v".padding(toLength: 43, withPad: "v", startingAt: 0)), state: "st")
        let c = try XCTUnwrap(URLComponents(url: req.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(c.host, "id.cumuluscloud.app")
        XCTAssertEqual(c.path, "/api/id/authorize")
        let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["client_id"], "scalvs")
        XCTAssertEqual(q["redirect_uri"], "https://scalvs.app/")
        XCTAssertEqual(q["code_challenge_method"], "S256")
        XCTAssertEqual(q["state"], "st")
        XCTAssertEqual(q["prompt"], "create")
    }

    func testAuthorizeURLSystemUsesReturnPage() {
        var architect = scalvs
        architect.clientId = "architect"
        architect.signIn = .system
        architect.returnURL = URL(string: "https://rchtch.app/cid-return.html?to=desktop")
        architect.callbackScheme = "architect"
        let req = CumulusID(product: architect).authorizeRequest(issuer: architect.issuers[0], home: architect.home, create: false)
        XCTAssertEqual(req.redirectURI.absoluteString, "https://rchtch.app/cid-return.html?to=desktop")
        XCTAssertFalse(req.url.absoluteString.contains("prompt="))
    }

    func testReturnDetection() {
        let req = CumulusID(product: scalvs).authorizeRequest(issuer: scalvs.issuers[0], home: scalvs.home, create: false, state: "abc")
        XCTAssertTrue(CumulusID.isReturn(URL(string: "https://scalvs.app/?code=c1&state=abc")!, for: req))
        XCTAssertTrue(CumulusID.isReturn(URL(string: "https://scalvs.app/?error=access_denied&state=abc")!, for: req))
        XCTAssertFalse(CumulusID.isReturn(URL(string: "https://scalvs.app/")!, for: req))
        XCTAssertFalse(CumulusID.isReturn(URL(string: "https://evil.example/?code=c1&state=abc")!, for: req))
        XCTAssertFalse(CumulusID.isReturn(URL(string: "https://id.cumuluscloud.app/?code=c1")!, for: req))
    }

    func testIssuerRoutes() {
        let cid = CumulusID(product: scalvs)
        XCTAssertEqual(cid.route(URL(string: "https://id.cumuluscloud.app/api/id/authorize?prompt=create")!), .authorize(create: true))
        XCTAssertEqual(cid.route(URL(string: "https://ru.id.cumuluscloud.app/api/id/authorize")!), .authorize(create: false))
        XCTAssertEqual(cid.route(URL(string: "https://id.cumuluscloud.app/api/id/end?token=x")!), .end)
        XCTAssertNil(cid.route(URL(string: "https://id.cumuluscloud.app/")!))
        XCTAssertNil(cid.route(URL(string: "https://scalvs.app/api/id/authorize")!))
    }

    func testTokenParsing() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let body = #"{"access_token":"tok","expires_in":120,"profile":{"email":"a@b.c","cid":"1"}}"#
        let s = try CumulusID.parseToken(Data(body.utf8), status: 200, now: now)
        XCTAssertEqual(s.token, "tok")
        XCTAssertEqual(s.until, now.addingTimeInterval(120))
        XCTAssertEqual(s.displayName, "a@b.c")
        XCTAssertTrue(s.isValid(at: now))
        XCTAssertFalse(s.isValid(at: now.addingTimeInterval(61)))
        XCTAssertThrowsError(try CumulusID.parseToken(Data(#"{"error":"invalid_grant"}"#.utf8), status: 400, now: now)) { error in
            XCTAssertEqual(error as? CumulusIDError, .server("invalid_grant"))
        }
    }

    func testKeepsInApp() {
        XCTAssertTrue(scalvs.keepsInApp(URL(string: "https://scalvs.app/x")!))
        XCTAssertTrue(scalvs.keepsInApp(URL(string: "https://RU.scalvs.app/")!))
        XCTAssertFalse(scalvs.keepsInApp(URL(string: "https://example.com/")!))
        XCTAssertFalse(scalvs.keepsInApp(URL(string: "mailto:a@b.c")!))
    }

    func testSessionScriptIsScopedAndEscaped() {
        let s = CumulusSession(token: "t</script>", profileJSON: #"{"email":"a@b.c"}"#, until: Date(timeIntervalSince1970: 2))
        let script = Handoff.sessionScript(product: scalvs, session: s)
        XCTAssertTrue(script.contains(#""cumulus-id:scalvs""#))
        XCTAssertTrue(script.contains(#"["scalvs.app","ru.scalvs.app"]"#))
        XCTAssertFalse(script.contains("</script>"))
        XCTAssertTrue(script.contains(#""until":2000"#))
    }

    func testHandoffFragment() throws {
        var p = scalvs
        let s = CumulusSession(token: "t", profileJSON: "{}", until: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(Handoff.startURL(product: p, home: p.home, session: s), p.home)
        p.handoffFragment = true
        let url = Handoff.startURL(product: p, home: p.home, session: s)
        let fragment = try XCTUnwrap(url.fragment)
        XCTAssertTrue(fragment.hasPrefix("cid_handoff="))
        let data = try XCTUnwrap(Base64URL.decode(String(fragment.dropFirst("cid_handoff=".count))))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["token"] as? String, "t")
        XCTAssertEqual(url.path, "/")
    }

    func testPageViewPropertiesDropQueryAndFragment() {
        let props = ProductAnalytics.pageProperties(URL(string: "https://scalvs.app/a/b?email=x#tok")!)
        XCTAssertEqual(props?["[Amplitude] Page Location"], "https://scalvs.app/a/b")
        XCTAssertEqual(props?["[Amplitude] Page Path"], "/a/b")
        XCTAssertNil(ProductAnalytics.pageProperties(URL(string: "about:blank")!))
    }

    @MainActor
    func testAnalyticsOffWithoutKeyOrFlag() {
        XCTAssertFalse(ProductAnalytics(product: scalvs, apiKey: nil).isEnabled)
        XCTAssertFalse(ProductAnalytics(product: scalvs, apiKey: "$(AMPLITUDE_API_KEY)").isEnabled)
        var veil = scalvs
        veil.analytics = false
        XCTAssertFalse(ProductAnalytics(product: veil, apiKey: "0123456789abcdef").isEnabled)
    }

    func testBundledProductFilesDecode() throws {
        // Every Apps/*/Product.json in the repo must decode and name a real client.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../Apps").standardizedFileURL
        let dirs = try FileManager.default.contentsOfDirectory(at: repo, includingPropertiesForKeys: nil)
        var count = 0
        for dir in dirs where FileManager.default.fileExists(atPath: dir.appendingPathComponent("Product.json").path) {
            let p = try ProductConfig.decode(Data(contentsOf: dir.appendingPathComponent("Product.json")))
            XCTAssertFalse(p.clientId.isEmpty, dir.lastPathComponent)
            XCTAssertEqual(p.home.scheme, "https", dir.lastPathComponent)
            XCTAssertFalse(p.issuers.isEmpty, dir.lastPathComponent)
            if p.signIn == .system {
                XCTAssertNotNil(p.returnURL, dir.lastPathComponent)
                XCTAssertNotNil(p.callbackScheme, dir.lastPathComponent)
            }
            count += 1
        }
        XCTAssertGreaterThan(count, 0)
    }
}

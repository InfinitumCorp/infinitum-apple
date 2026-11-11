import AmplitudeSwift
import Foundation

/// Amplitude for commercial products: page views and sessions only, US region.
/// Off: autocapture of forms and text, session replay, remote config, diagnostics, IP, city, DMA,
/// carrier and advertising ids. No user id is set, and no query strings or fragments are sent.
@MainActor
public final class ProductAnalytics {
    private let amplitude: Amplitude?

    /// `apiKey` is the public Amplitude API key from the build (never the secret key). Without a key,
    /// or for a product with analytics off, nothing is sent.
    public init(product: ProductConfig, apiKey: String?) {
        let key = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard product.analytics, !key.isEmpty, !key.hasPrefix("$(") else {
            amplitude = nil
            return
        }
        amplitude = Amplitude(configuration: Configuration(
            apiKey: key,
            serverZone: .US,
            trackingOptions: Self.trackingOptions(),
            autocapture: .sessions,
            enableAutoCaptureRemoteConfig: false,
            enableDiagnostics: false
        ))
    }

    public var isEnabled: Bool { amplitude != nil }

    static func trackingOptions() -> TrackingOptions {
        TrackingOptions()
            .disableTrackIpAddress()
            .disableTrackCity()
            .disableTrackDMA()
            .disableTrackCarrier()
            .disableTrackIDFV()
    }

    /// One page view: domain and path only.
    public func pageView(_ url: URL) {
        guard let amplitude, let props = Self.pageProperties(url) else { return }
        _ = amplitude.track(eventType: "[Amplitude] Page Viewed", eventProperties: props)
    }

    nonisolated static func pageProperties(_ url: URL) -> [String: String]? {
        guard let scheme = url.scheme, scheme == "https" || scheme == "http", let host = url.host else { return nil }
        let path = url.path.isEmpty ? "/" : url.path
        return [
            "[Amplitude] Page Domain": host,
            "[Amplitude] Page Path": path,
            "[Amplitude] Page Location": "\(scheme)://\(host)\(path)",
        ]
    }
}

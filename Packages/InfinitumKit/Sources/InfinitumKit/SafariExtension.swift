#if os(macOS)
import SafariServices

/// Opens Safari's settings at this app's web extension so people can turn it on.
public enum SafariExtension {
    public static func showSettings(_ identifier: String) {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: identifier) { _ in }
    }
}
#endif

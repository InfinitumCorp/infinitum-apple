import SafariServices

/// Native side of the :\ARCHITECT\ Safari Web Extension. The extension does all its work in
/// JavaScript; this only answers browser.runtime.sendNativeMessage so Safari can load it.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["ok": true]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}

import InfinitumKit
import SwiftUI

/// Every product app is this same entry point; `Product.json` in the bundle says which product.
@main
struct InfinitumShellApp: App {
    @StateObject private var model = AppModel(product: .bundled())

    var body: some Scene {
        WindowGroup(model.product.name) {
            RootView(model: model)
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}

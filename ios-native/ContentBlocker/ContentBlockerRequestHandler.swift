import Foundation

/// Hands Safari the EasyList rules (`easylist.json`, made by `tools/update-blocking-lists.sh`).
/// Once turned on in Settings, they apply in the app's Safari sheet (and in Safari). The other
/// blocking lists are for the built-in browser only.
final class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = NSExtensionItem()
        if let url = Bundle.main.url(forResource: "easylist", withExtension: "json"),
           let attachment = NSItemProvider(contentsOf: url) {
            item.attachments = [attachment]
        }
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}

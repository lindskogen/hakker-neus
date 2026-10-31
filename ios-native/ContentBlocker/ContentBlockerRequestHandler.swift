import Foundation

/// Hands Safari the EasyList rules (`blockerList.json`, made by `tools/easylist-to-webkit.py`).
/// Once turned on in Settings, they apply in the app's Safari sheet (and in Safari).
final class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = NSExtensionItem()
        if let url = Bundle.main.url(forResource: "blockerList", withExtension: "json"),
           let attachment = NSItemProvider(contentsOf: url) {
            item.attachments = [attachment]
        }
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}

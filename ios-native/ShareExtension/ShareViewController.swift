import UIKit
import UniformTypeIdentifiers

/// "Search on HN" in the share sheet: opens HakkerNeus with the shared link in the search field,
/// to find the Hacker News discussions of a page open in Safari.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { await openApp() }
    }

    private func openApp() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var link: String?
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                link = url.absoluteString
                break
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                link = text
                break
            }
        }

        var components = URLComponents()
        components.scheme = "hakkerneus"
        components.host = "search"
        components.queryItems = [URLQueryItem(name: "q", value: link ?? "")]
        if let url = components.url { open(url) }
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Extensions can't open URLs directly; the host application in the responder chain can.
    private func open(_ url: URL) {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url)
                return
            }
            responder = current.next
        }
    }
}

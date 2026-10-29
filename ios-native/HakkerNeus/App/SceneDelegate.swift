import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = Theme.Color.backgroundDark

        let coordinator = AppCoordinator(window: window)
        coordinator.start()
        if let shortcut = connectionOptions.shortcutItem {
            _ = coordinator.handleShortcut(shortcut.type)
        }

        self.window = window
        self.coordinator = coordinator
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(coordinator?.handleShortcut(shortcutItem.type) ?? false)
    }
}

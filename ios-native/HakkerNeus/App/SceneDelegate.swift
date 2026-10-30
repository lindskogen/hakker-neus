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
        coordinator.start(restoring: Self.restorationState(for: session))
        if let shortcut = connectionOptions.shortcutItem {
            _ = coordinator.handleShortcut(shortcut.type)
        }

        self.window = window
        self.coordinator = coordinator
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        coordinator?.restorationState.save()
    }

    private static func restorationState(for session: UISceneSession) -> RestorationState? {
        #if DEBUG
        // UI tests start from a clean slate unless they're testing restoration.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-NoStateRestoration") || arguments.contains(CommentsSinkClient.launchArgument) {
            return nil
        }
        #endif
        return RestorationState.load()
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(coordinator?.handleShortcut(shortcutItem.type) ?? false)
    }
}

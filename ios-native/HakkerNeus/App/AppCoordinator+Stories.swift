import UIKit

/// Story row behaviour shared by the front page and the saved list.
extension AppCoordinator {
    func configure(_ cell: StoryCell, with story: Story, backgroundColor: UIColor, inSavedList: Bool) {
        let jump = inSavedList
            ? UIAccessibilityCustomAction(name: "Front Page") { [weak self] _ in
                self?.showFrontPage()
                return true
            }
            : UIAccessibilityCustomAction(name: "Saved Stories") { [weak self] _ in
                self?.showSavedStories()
                return true
            }

        cell.configure(
            with: story,
            backgroundColor: backgroundColor,
            isSaved: savedStories.isSaved(story.id),
            showsSavedBadge: !inSavedList,
            extraAccessibilityActions: [jump]
        )
        cell.onToggleSaved = { [weak self] in self?.savedStories.toggle(story) }
        cell.onOpenComments = { [weak self] in self?.showComments(for: story) }
    }

    /// Tapping a row opens the link, or the comments for self posts.
    func select(_ story: Story) {
        if let url = story.url {
            open(url)
        } else {
            showComments(for: story)
        }
    }

    func contextMenuConfiguration(for story: Story, sourceView: UIView) -> UIContextMenuConfiguration {
        UIContextMenuConfiguration(
            identifier: story.id as NSNumber,
            previewProvider: { [weak self] in self?.makePreview(for: story) },
            actionProvider: { [weak self, weak sourceView] _ in
                guard let self, let sourceView else { return nil }
                return storyMenu(for: story, sourceView: sourceView, includeComments: true)
            }
        )
    }

    func commitContextMenuPreview(_ animator: UIContextMenuInteractionCommitAnimating) {
        guard let preview = animator.previewViewController else { return }
        animator.preferredCommitStyle = .pop
        animator.addCompletion { [weak self] in
            self?.commitPreview(preview)
        }
    }
}

/// One-time hint that the saved list lives behind the front page.
extension AppCoordinator {
    private static let savedHintKey = "didShowSavedStoriesHint"

    func savedStoryChanged(_ id: Int?) {
        guard let id, savedStories.isSaved(id),
              !defaults.bool(forKey: Self.savedHintKey),
              navigationController.topViewController === frontPage
        else { return }
        defaults.set(true, forKey: Self.savedHintKey)

        // Wait for the swiped row to settle first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.playSavedHint()
        }
    }

    /// Nudges the front page to the right, showing a heart in the gap at the left edge,
    /// where the swipe to the saved list starts, then springs back.
    private func playSavedHint() {
        guard navigationController.topViewController === frontPage,
              navigationController.presentedViewController == nil,
              !UIAccessibility.isReduceMotionEnabled
        else { return }

        let heart = UIImageView(image: UIImage(systemName: "heart.fill"))
        heart.tintColor = .white
        heart.preferredSymbolConfiguration = .init(pointSize: 26)
        heart.sizeToFit()
        heart.center = CGPoint(x: 32, y: window.bounds.midY)
        heart.alpha = 0
        // Behind the navigation controller's view, so it's only visible in the gap.
        window.insertSubview(heart, at: 0)

        let page = navigationController.view!
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut) {
            page.transform = CGAffineTransform(translationX: 64, y: 0)
            heart.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.6, delay: 0.6, usingSpringWithDamping: 0.75, initialSpringVelocity: 0) {
                page.transform = .identity
                heart.alpha = 0
            } completion: { _ in
                heart.removeFromSuperview()
            }
        }
    }
}

import UIKit

/// lobste.rs rows and menus: the HN ones (in `AppCoordinator+Stories` and `storyMenu`) without
/// voting, with user pages and discussion links on lobste.rs. Read-only for now.
extension AppCoordinator {
    func configureLobsters(_ cell: StoryCell, with story: Story, backgroundColor: UIColor, inSavedList: Bool, compact: Bool = false, openedFrom: OpenedFrom? = nil) {
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
            isUpvoted: false,
            score: story.score,
            isVisited: visitedStories.isVisited(story.id),
            isActive: split.activeStoryID == story.id,
            canUpvote: false,
            newComments: visitedStories.newCommentCount(for: story),
            showsSavedBadge: !inSavedList,
            compact: compact,
            extraAccessibilityActions: [jump]
        )
        cell.onToggleSaved = { [weak self] in self?.savedStories.toggle(story) }
        cell.onToggleUpvote = nil
        let origin = openedFrom ?? (compact ? .detail : .list)
        cell.onOpenComments = { [weak self] in self?.showComments(for: story, from: origin) }
        cell.onSwipeBegan = { [weak self] in self?.prefetchComments(for: story) }
    }

    func lobstersContextMenuConfiguration(for story: Story, sourceView: UIView) -> UIContextMenuConfiguration {
        prefetchComments(for: story)
        return UIContextMenuConfiguration(
            identifier: story.id as NSNumber,
            previewProvider: { [weak self] in self?.makePreview(for: story) },
            actionProvider: { [weak self, weak sourceView] _ in
                guard let self, let sourceView else { return nil }
                return lobstersStoryMenu(for: story, sourceView: sourceView, includeComments: true)
            }
        )
    }

    func lobstersStoryMenu(for story: Story, sourceView: UIView, includeComments: Bool) -> UIMenu {
        let origin: OpenedFrom = includeComments ? .list : .detail
        var open: [UIMenuElement] = []
        if includeComments {
            open.append(UIAction(
                title: "Comments",
                subtitle: story.commentCount == 1 ? "1 comment" : "\(story.commentCount) comments",
                image: UIImage(systemName: "bubble.left.and.bubble.right")
            ) { [weak self] _ in
                self?.showComments(for: story, from: origin)
            })
        }
        if let url = story.url {
            open.append(UIAction(title: "Open Link", subtitle: url.host(), image: UIImage(systemName: "safari")) { [weak self] _ in
                self?.visitedStories.markOpened(story)
                self?.open(url, story: story, from: origin)
            })
        }

        let isSaved = savedStories.isSaved(story.id)
        let save = UIAction(
            title: isSaved ? "Unsave" : "Save",
            image: UIImage(systemName: isSaved ? "heart.slash" : "heart")
        ) { [weak self] _ in
            self?.savedStories.toggle(story)
        }

        let discussion = Lobsters.storyURL(story.id)
        let shareURL = story.url ?? discussion
        let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self, weak sourceView] _ in
            guard let sourceView else { return }
            self?.share(shareURL, from: sourceView)
        }
        let copy = UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
            UIPasteboard.general.url = shareURL
        }
        let copyComments = story.url == nil ? nil : UIAction(
            title: "Copy Comments Link", image: UIImage(systemName: "bubble.left.and.text.bubble.right")
        ) { _ in
            UIPasteboard.general.url = discussion
        }

        var user: [UIMenuElement] = []
        if let author = story.author {
            // Their page on lobste.rs: user pages in the app are HN's.
            user.append(UIAction(title: author, image: UIImage(systemName: "person")) { [weak self] _ in
                self?.open(Lobsters.userURL(author), from: origin)
            })
        }

        let sections: [[UIMenuElement]] = [open, [save], [share, copy] + [copyComments].compactMap { $0 }, user]
        return UIMenu(children: sections.filter { !$0.isEmpty }.map { UIMenu(options: .displayInline, children: $0) })
    }
}

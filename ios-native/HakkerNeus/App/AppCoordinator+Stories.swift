import UIKit

/// Story row behaviour shared by the front page and the saved list.
extension AppCoordinator {
    /// - Parameter openedFrom: Where the row's comments open from; by default a list, or the side
    ///   column for compact rows (user pages).
    func configure(_ cell: StoryCell, with story: Story, backgroundColor: UIColor, inSavedList: Bool, compact: Bool = false, openedFrom: OpenedFrom? = nil) {
        if story.isLobsters {
            return configureLobsters(cell, with: story, backgroundColor: backgroundColor, inSavedList: inSavedList, compact: compact, openedFrom: openedFrom)
        }
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
            isUpvoted: session.isUpvoted(story.id),
            score: session.displayedScore(for: story),
            isVisited: visitedStories.isVisited(story.id),
            isActive: split.activeStoryID == story.id,
            canUpvote: session.isSignedIn,
            newComments: visitedStories.newCommentCount(for: story),
            showsSavedBadge: !inSavedList,
            compact: compact,
            extraAccessibilityActions: [jump]
        )
        cell.onToggleSaved = { [weak self] in self?.savedStories.toggle(story) }
        cell.onToggleUpvote = { [weak self] in self?.toggleVote(story) }
        // Compact rows are usually on user pages, which are in the side column when the window is wide.
        let origin = openedFrom ?? (compact ? .detail : .list)
        cell.onOpenComments = { [weak self] in self?.showComments(for: story, from: origin) }
        cell.onSwipeBegan = { [weak self] in self?.prefetchComments(for: story) }
    }

    /// Tapping a row opens the link, or the comments for self posts.
    func select(_ story: Story, from origin: OpenedFrom = .list) {
        if let url = story.url {
            visitedStories.markOpened(story)
            open(url, story: story, from: origin)
        } else {
            showComments(for: story, from: origin)
        }
    }

    func contextMenuConfiguration(for story: Story, sourceView: UIView) -> UIContextMenuConfiguration {
        if story.isLobsters { return lobstersContextMenuConfiguration(for: story, sourceView: sourceView) }
        prefetchComments(for: story)
        return UIContextMenuConfiguration(
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

// MARK: Prefetching

extension AppCoordinator {
    /// Starts fetching a story's comments as soon as the user shows interest (touching the row,
    /// starting a swipe, opening its menu), so the comments screen usually opens already loaded.
    func prefetchComments(for story: Story) {
        itemCache.prefetch(id: story.id)
    }

    func prefetchItem(id: Int) {
        itemCache.prefetch(id: id)
    }

    /// Fetches the profile and first stories of a user whose page is one tap away.
    func prefetchUser(_ name: String) {
        userCache.prefetch(name)
    }

    /// On Wi-Fi, fetches the comments of the rows on screen once scrolling stops.
    func prefetchVisible(_ stories: [Story]) {
        guard NetworkConditions.shared.allowsSpeculativeFetching else { return }
        for story in stories.prefix(10) where story.commentCount > 0 {
            itemCache.prefetch(id: story.id)
        }
    }
}

import UIKit

/// The saved stories or comments, newest first: one of the sidebar's places. Story rows work
/// like on the front page, in red instead of orange; comments are listed like on user pages.
final class SavedStoriesViewController: UIViewController, UICollectionViewDelegate, EdgeOnlySwipeBack, StoryTransitionSource {
    private enum Section { case main }

    enum Tab: Int, TextTab {
        case stories, comments

        var title: String {
            switch self {
            case .stories: "Stories"
            case .comments: "Comments"
            }
        }
    }

    private enum Item: Hashable {
        case story(Int)
        case comment(Int)
    }

    private unowned let coordinator: AppCoordinator
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var stories: [Story.ID: Story] = [:]
    private var comments: [Int: SavedComment] = [:]
    private var commentBodies: [Int: CommentBody] = [:]
    private var selectedTab = Tab.stories
    private let emptyView = FullPageStateView()
    private let topFill = TopFillView()
    private weak var savedHeader: SavedHeaderView?
    private var pendingReload: DispatchWorkItem?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark

        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        // Clear, so the list doesn't paint over the empty state in `backgroundView`.
        list.backgroundColor = .clear
        list.separatorConfiguration.color = .black
        list.separatorConfiguration.bottomSeparatorInsets = .zero
        list.headerMode = .supplementary

        let layout = UICollectionViewCompositionalLayout { _, environment in
            let section = NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
            // Plain lists pin headers; the profile header scrolls with the rows.
            for item in section.boundarySupplementaryItems {
                item.pinToVisibleBounds = false
            }
            return section
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = Theme.Color.backgroundDark
        collectionView.indicatorStyle = .white
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "saved.list"
        view.addSubview(collectionView)
        topFill.install(in: collectionView)
        // Room to scroll the last row out from under the corner button.
        collectionView.contentInset.bottom = 64
        // The dark header is first, so it's what reaches up under the clock.
        topFill.color = Theme.Color.backgroundDark

        emptyView.isAccessibilityElement = true
        emptyView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Front Page") { [unowned self] _ in
                coordinator.showFrontPage()
                return true
            },
        ]

        let cell = UICollectionView.CellRegistration<StoryCell, Item> { [unowned self] cell, indexPath, item in
            guard case .story(let id) = item, let story = stories[id] else { return }
            // Quiet rows, like on the profile.
            coordinator.configure(cell, with: story, backgroundColor: Theme.Color.backgroundDark, inSavedList: true, compact: true, openedFrom: .list)
        }
        let commentCell = UICollectionView.CellRegistration<UserCommentCell, Item> { [unowned self] cell, _, item in
            guard case .comment(let id) = item, let comment = comments[id] else { return }
            let body = commentBodies[id] ?? CommentBody(html: comment.text)
            commentBodies[id] = body
            cell.configure(with: comment, body: body)
            cell.onLinkTap = { [unowned self] in coordinator.open($0) }
            cell.linkMenu = { [unowned self] url, source in coordinator.linkMenu(for: url, sourceView: source) }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .story: collectionView.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: item)
            case .comment: collectionView.dequeueConfiguredReusableCell(using: commentCell, for: indexPath, item: item)
            }
        }
        let header = UICollectionView.SupplementaryRegistration<SavedHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [unowned self] view, _, _ in
            savedHeader = view
            view.horizontalMargin = systemMinimumLayoutMargins.leading
            configureSavedHeader()
            view.onTab = { [unowned self] tab in
                selectedTab = tab
                reload(animated: false)
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }

        for name in [SavedStoriesStore.didChange, SavedCommentsStore.didChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(savedStoriesChanged), name: name, object: nil)
        }
        for name in [VisitedStoriesStore.didChange, HNSession.votesChanged, SplitViewController.activeStoryDidChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(visitedStoryChanged(_:)), name: name, object: nil)
        }
        reload(animated: false)
    }

    @objc private func savedStoriesChanged() {
        // Let a swiped row spring back before it's removed from the list.
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload(animated: true) }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    @objc private func visitedStoryChanged(_ notification: Notification) {
        guard let id = notification.object as? Int, dataSource.indexPath(for: .story(id)) != nil else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([.story(id)])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func reload(animated: Bool) {
        let all = coordinator.savedStories.all
        stories = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let allComments = coordinator.savedComments.all
        comments = Dictionary(allComments.map { ($0.id, $0) }, uniquingKeysWith: { $1 })

        let items: [Item] = selectedTab == .stories ? all.map { .story($0.id) } : allComments.map { .comment($0.id) }
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items)
        // Row colors depend on position, so rows that stay are refreshed too.
        let existing = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(items.filter(existing.contains))
        dataSource.apply(snapshot, animatingDifferences: animated && !UIAccessibility.isReduceMotionEnabled)

        let empty = selectedTab == .stories ? "No saved stories" : "No saved comments"
        emptyView.state = .message(systemImage: selectedTab == .stories ? "heart" : "text.bubble", text: empty)
        emptyView.accessibilityLabel = empty
        collectionView.backgroundView = items.isEmpty ? emptyView : nil
        configureSavedHeader()
    }

    private func configureSavedHeader() {
        savedHeader?.configure(savedCount: stories.count, savedCommentCount: comments.count, tab: selectedTab)
    }

    private func story(at indexPath: IndexPath) -> Story? {
        guard case .story(let id) = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return stories[id]
    }

    private func comment(at indexPath: IndexPath) -> SavedComment? {
        guard case .comment(let id) = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return comments[id]
    }


    // MARK: Transition into comments

    func transitionViews(forStory id: Int) -> (card: UIView, title: UIView)? {
        guard let indexPath = dataSource.indexPath(for: .story(id)) else { return nil }
        return (collectionView.cellForItem(at: indexPath) as? StoryCell)?.transitionViews
    }

    // MARK: Restoration

    /// Where to scroll back to once the stories are showing, when restoring after a relaunch.
    var pendingAnchor: RestorationState.ScrollAnchor?

    var scrollAnchor: RestorationState.ScrollAnchor? {
        guard isViewLoaded, let (indexPath, offset) = collectionView.topAnchorItem,
              case .story(let id) = dataSource.itemIdentifier(for: indexPath)
        else { return nil }
        return .init(id: id, offset: offset)
    }

    private func applyPendingAnchor() {
        guard let anchor = pendingAnchor, view.window != nil, collectionView.bounds.height > 0 else { return }
        pendingAnchor = nil
        if let indexPath = dataSource.indexPath(for: .story(anchor.id)) {
            collectionView.scroll(toAnchor: indexPath, offset: anchor.offset)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !stories.isEmpty { applyPendingAnchor() }
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        if let story = story(at: indexPath) {
            coordinator.select(story)
        } else if let comment = comment(at: indexPath) {
            // The comments screen finds the comment's story and scrolls to it.
            coordinator.showComments(id: comment.id, from: .list)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        story(at: indexPath).map(coordinator.prefetchComments)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first,
              let cell = collectionView.cellForItem(at: indexPath)
        else { return nil }
        if let story = story(at: indexPath) {
            return coordinator.contextMenuConfiguration(for: story, sourceView: cell)
        }
        guard let comment = comment(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [unowned self, weak cell] _ in
            let open = UIAction(title: "Open Thread", image: UIImage(systemName: "bubble.left.and.bubble.right")) { [unowned self] _ in
                coordinator.showComments(id: comment.id, from: .list)
            }
            let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [unowned self] _ in
                coordinator.share(comment.hackerNewsURL, from: cell ?? collectionView)
            }
            let copyText = UIAction(title: "Copy Text", image: UIImage(systemName: "doc.on.doc")) { [unowned self] _ in
                UIPasteboard.general.string = commentBodies[comment.id]?.plainText ?? ""
            }
            let unsave = UIAction(title: "Unsave", image: UIImage(systemName: "heart.slash"), attributes: .destructive) { [unowned self] _ in
                coordinator.savedComments.remove(comment.id)
            }
            return UIMenu(children: [
                UIMenu(options: .displayInline, children: [open]),
                UIMenu(options: .displayInline, children: [share, copyText]),
                UIMenu(options: .displayInline, children: [unsave]),
            ])
        })
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        coordinator.commitContextMenuPreview(animator)
    }
}

// MARK: Scrolling to the top

extension SavedStoriesViewController: TopLevelScreen {
    var scrollView: UIScrollView? { isViewLoaded ? collectionView : nil }
}

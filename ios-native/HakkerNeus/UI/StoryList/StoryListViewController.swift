import UIKit

/// The front page (`NewsList.tsx`).
/// Swiping right in the content area saves a row here, so only the edge swipe goes back (to the saved list).
final class StoryListViewController: UIViewController, UICollectionViewDelegate, EdgeOnlySwipeBack, StoryTransitionSource {
    private enum Section { case main }

    private let feed: TopStoriesFeed
    private unowned let coordinator: AppCoordinator

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Story.ID>!
    private var stories: [Story.ID: Story] = [:]
    private let stateView = FullPageStateView()
    private let skeleton = SkeletonListView()
    private let refreshControl = RefreshControl()
    private let topFill = TopFillView()
    private let offlineBanner = OfflineBanner()

    private var isLoadingMore = false {
        didSet { footer?.isLoading = isLoadingMore }
    }
    private weak var footer: LoadingFooterView?

    init(feed: TopStoriesFeed, coordinator: AppCoordinator) {
        self.feed = feed
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark

        configureCollectionView()
        configureDataSource()

        for name in [SavedStoriesStore.didChange, VisitedStoriesStore.didChange, HNSession.votesChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(storyStateChanged(_:)), name: name, object: nil)
        }

        if feed.stories.isEmpty {
            collectionView.backgroundView = skeleton
            Task { await reload() }
        } else {
            // Restored from the last launch: show it as it was; pull to refresh gets a new ranking.
            show(feed.stories, replacing: true)
        }
    }

    private func configureCollectionView() {
        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        // Clear, so the list doesn't paint over the loading and error states in `backgroundView`.
        list.backgroundColor = .clear
        list.footerMode = .supplementary
        list.separatorConfiguration.color = .black
        list.separatorConfiguration.bottomSeparatorInsets = .zero

        let layout = UICollectionViewCompositionalLayout { _, environment in
            let section = NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
            // Plain lists pin footers to the screen; the loading footer should scroll with the rows.
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
        collectionView.accessibilityIdentifier = "stories.list"

        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        topFill.install(in: collectionView)
        offlineBanner.install(in: view)
        topFill.color = Palette.storyBackground(at: 0)
    }

    private func configureDataSource() {
        let cell = UICollectionView.CellRegistration<StoryCell, Story.ID> { [unowned self] cell, indexPath, id in
            guard let story = stories[id] else { return }
            coordinator.configure(cell, with: story, backgroundColor: Palette.storyBackground(at: indexPath.item), inSavedList: false)
        }
        let footer = UICollectionView.SupplementaryRegistration<LoadingFooterView>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [unowned self] view, _, _ in
            self.footer = view
            view.isLoading = isLoadingMore
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath)
        }
    }

    // MARK: Loading

    @objc private func refresh() {
        Task { await reload() }
    }

    private func reload() async {
        let update: () -> Void
        do {
            let all = try await feed.reload()
            update = { [self] in
                show(all, replacing: true)
                collectionView.backgroundView = nil
                applyPendingAnchor()
            }
        } catch is CancellationError {
            return
        } catch {
            update = { [self] in
                if stories.isEmpty {
                    stateView.backgroundColor = Theme.Color.backgroundDark
                    stateView.state = .error(error)
                    collectionView.backgroundView = stateView
                } else {
                    // Keep the stories that are showing; just say why they didn't change.
                    offlineBanner.show("Offline · couldn't refresh", hideAfter: 2.5)
                }
            }
        }
        refreshControl.endRefreshing(applying: update)
    }

    private func loadMore() {
        guard !isLoadingMore, feed.hasMore, !stories.isEmpty else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            // A failed page is retried the next time the end of the list scrolls into view.
            if let all = try? await feed.loadNextPage() {
                show(all, replacing: false)
            }
        }
    }

    private func show(_ all: [Story], replacing: Bool) {
        stories = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        var snapshot = NSDiffableDataSourceSnapshot<Section, Story.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(all.map(\.id))
        if replacing {
            // Scores and comment counts change between loads; refresh rows that stay.
            let existing = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(all.map(\.id).filter(existing.contains))
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// A story was saved, unsaved or read: refresh its row.
    @objc private func storyStateChanged(_ notification: Notification) {
        var snapshot = dataSource.snapshot()
        if let id = notification.object as? Int {
            guard snapshot.indexOfItem(id) != nil else { return }
            snapshot.reconfigureItems([id])
        } else {
            // Many changed at once (an import).
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func story(at indexPath: IndexPath) -> Story? {
        dataSource.itemIdentifier(for: indexPath).flatMap { stories[$0] }
    }


    // MARK: Transition into comments

    func transitionViews(forStory id: Int) -> (card: UIView, title: UIView)? {
        guard let indexPath = dataSource.indexPath(for: id) else { return nil }
        return (collectionView.cellForItem(at: indexPath) as? StoryCell)?.transitionViews
    }

    // MARK: Restoration

    /// Where to scroll back to once the stories are showing, when restoring after a relaunch.
    var pendingAnchor: RestorationState.ScrollAnchor?

    /// The loaded front page, so the next launch can show the same list.
    var feedSnapshot: TopStoriesFeed.Snapshot? { feed.snapshot }

    func restoreFeed(_ snapshot: TopStoriesFeed.Snapshot) {
        feed.restore(snapshot)
    }

    var scrollAnchor: RestorationState.ScrollAnchor? {
        guard isViewLoaded, let (indexPath, offset) = collectionView.topAnchorItem,
              let id = dataSource.itemIdentifier(for: indexPath)
        else { return nil }
        return .init(id: id, offset: offset)
    }

    private func applyPendingAnchor() {
        guard let anchor = pendingAnchor, view.window != nil, collectionView.bounds.height > 0 else { return }
        pendingAnchor = nil
        if let indexPath = dataSource.indexPath(for: anchor.id) {
            collectionView.scroll(toAnchor: indexPath, offset: anchor.offset)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !stories.isEmpty { applyPendingAnchor() }
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item >= stories.count - 5 {
            loadMore()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let story = story(at: indexPath) else { return }
        coordinator.select(story)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first,
              let story = story(at: indexPath),
              let cell = collectionView.cellForItem(at: indexPath)
        else { return nil }

        return coordinator.contextMenuConfiguration(for: story, sourceView: cell)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        coordinator.commitContextMenuPreview(animator)
    }
}

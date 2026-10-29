import UIKit

/// The front page (`NewsList.tsx`).
/// Swiping right in the content area saves a row here, so only the edge swipe goes back (to the saved list).
final class StoryListViewController: UIViewController, UICollectionViewDelegate, EdgeOnlySwipeBack {
    private enum Section { case main }

    private let feed: TopStoriesFeed
    private unowned let coordinator: AppCoordinator

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Story.ID>!
    private var stories: [Story.ID: Story] = [:]
    private let stateView = FullPageStateView()
    private let refreshControl = RefreshControl()

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

        NotificationCenter.default.addObserver(
            self, selector: #selector(savedStoriesChanged(_:)), name: SavedStoriesStore.didChange, object: nil
        )

        stateView.backgroundColor = Theme.Color.backgroundOrange
        stateView.state = .loading
        collectionView.backgroundView = stateView
        Task { await reload() }
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
            }
        } catch is CancellationError {
            return
        } catch {
            update = { [self] in
                if stories.isEmpty {
                    stateView.backgroundColor = Theme.Color.backgroundDark
                    stateView.state = .error(error)
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

    @objc private func savedStoriesChanged(_ notification: Notification) {
        guard let id = notification.object as? Int, dataSource.indexPath(for: id) != nil else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([id])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func story(at indexPath: IndexPath) -> Story? {
        dataSource.itemIdentifier(for: indexPath).flatMap { stories[$0] }
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

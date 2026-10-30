import UIKit

/// Saved stories, newest first, behind the front page: swipe in from the left edge of the
/// front page to get here, and in from the right edge to go back.
/// Rows work like on the front page, in red instead of orange.
final class SavedStoriesViewController: UIViewController, UICollectionViewDelegate, ForwardNavigating {
    private enum Section { case main }

    private unowned let coordinator: AppCoordinator
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Story.ID>!
    private var stories: [Story.ID: Story] = [:]
    private let emptyView = FullPageStateView()
    private let topFill = TopFillView()
    private var pendingReload: DispatchWorkItem?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var forwardViewController: UIViewController? { coordinator.frontPage }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark

        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        // Clear, so the list doesn't paint over the empty state in `backgroundView`.
        list.backgroundColor = .clear
        list.separatorConfiguration.color = .black
        list.separatorConfiguration.bottomSeparatorInsets = .zero

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: list))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = Theme.Color.backgroundDark
        collectionView.indicatorStyle = .white
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "saved.list"
        view.addSubview(collectionView)
        topFill.install(in: collectionView)

        emptyView.state = .message(systemImage: "heart", text: "No saved stories")
        emptyView.isAccessibilityElement = true
        emptyView.accessibilityLabel = "No saved stories"
        emptyView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Front Page") { [unowned self] _ in
                coordinator.showFrontPage()
                return true
            },
        ]

        let cell = UICollectionView.CellRegistration<StoryCell, Story.ID> { [unowned self] cell, indexPath, id in
            guard let story = stories[id] else { return }
            coordinator.configure(cell, with: story, backgroundColor: Palette.savedStoryBackground(at: indexPath.item), inSavedList: true)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(savedStoriesChanged), name: SavedStoriesStore.didChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(visitedStoryChanged(_:)), name: VisitedStoriesStore.didChange, object: nil
        )
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
        guard let id = notification.object as? Int, dataSource.indexPath(for: id) != nil else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([id])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func reload(animated: Bool) {
        let all = coordinator.savedStories.all
        stories = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { $1 })

        var snapshot = NSDiffableDataSourceSnapshot<Section, Story.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(all.map(\.id))
        // Row colors depend on position, so rows that stay are refreshed too.
        let existing = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(all.map(\.id).filter(existing.contains))
        dataSource.apply(snapshot, animatingDifferences: animated && !UIAccessibility.isReduceMotionEnabled)

        collectionView.backgroundView = all.isEmpty ? emptyView : nil
        topFill.color = all.isEmpty ? nil : Palette.savedStoryBackground(at: 0)
    }

    private func story(at indexPath: IndexPath) -> Story? {
        dataSource.itemIdentifier(for: indexPath).flatMap { stories[$0] }
    }


    // MARK: Restoration

    /// Where to scroll back to once the stories are showing, when restoring after a relaunch.
    var pendingAnchor: RestorationState.ScrollAnchor?

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

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        if let story = story(at: indexPath) {
            coordinator.select(story)
        }
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

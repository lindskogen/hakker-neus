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

    /// Above the corner button: hides the read stories, then briefly offers to undo that.
    private let hideReadButton = UIButton(type: .system)
    private var hideReadLeading: NSLayoutConstraint!
    private var hideReadTrailing: NSLayoutConstraint!
    /// The stories the button just hid, while it offers to undo.
    private var justHidden: [Int]?
    private var undoTimer: Timer?
    /// Everything the feed has loaded, hidden stories included.
    private var feedStories: [Story] = []

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

        configureHideReadButton()
        NotificationCenter.default.addObserver(self, selector: #selector(colorThemeChanged), name: AppSettings.colorThemeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(placeHideReadButton), name: AppSettings.cornerButtonSideDidChange, object: nil)
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
        // Room to scroll the last row out from under the corner button.
        collectionView.contentInset.bottom = 64
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
        guard !isLoadingMore, feed.hasMore, !feedStories.isEmpty else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            // A failed page is retried the next time the end of the list scrolls into view.
            if let all = try? await feed.loadNextPage() {
                show(all, replacing: false)
            }
        }
    }

    private func show(_ all: [Story], replacing: Bool, animated: Bool = false) {
        feedStories = all
        let shown = all.filter { !coordinator.hiddenStories.isHidden($0.id) }
        stories = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        var snapshot = NSDiffableDataSourceSnapshot<Section, Story.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(shown.map(\.id))
        // Row colours depend on position, so rows that stay are refreshed when others go;
        // and scores and comment counts change between loads.
        if replacing || animated {
            let existing = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(shown.map(\.id).filter(existing.contains))
        }
        dataSource.apply(snapshot, animatingDifferences: animated && !UIAccessibility.isReduceMotionEnabled)
        updateHideReadButton()
        // Hiding can leave too few rows to scroll to the end, where the next page loads.
        if shown.count < 15 { loadMore() }
    }

    // MARK: Hide read stories

    private func configureHideReadButton() {
        var config: UIButton.Configuration
        if #available(iOS 26, *) {
            config = .glass()
        } else {
            config = .filled()
            config.baseBackgroundColor = UIColor(white: 0.25, alpha: 0.9)
        }
        config.preferredSymbolConfigurationForImage = .init(pointSize: 16, weight: .semibold)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        if #available(iOS 26, *) {
            config.symbolContentTransition = UISymbolContentTransition(.replace.downUp)
        }
        hideReadButton.configuration = config
        hideReadButton.accessibilityIdentifier = "hideRead"
        hideReadButton.alpha = 0
        hideReadButton.isHidden = true
        hideReadButton.addAction(UIAction { [unowned self] _ in hideReadTapped() }, for: .touchUpInside)

        hideReadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hideReadButton)
        // Stacked above the corner button (52pt, 10pt off the bottom), on the same side.
        NSLayoutConstraint.activate([
            hideReadButton.widthAnchor.constraint(equalToConstant: 44),
            hideReadButton.heightAnchor.constraint(equalToConstant: 44),
            hideReadButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -(Theme.padding + 52 + Theme.padding)),
        ])
        hideReadLeading = hideReadButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Theme.padding * 2 + 26)
        hideReadTrailing = hideReadButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -(Theme.padding * 2 + 26))
        placeHideReadButton()
        updateHideReadButton()
    }

    @objc private func placeHideReadButton() {
        let onLeft = coordinator.settings.cornerButtonOnLeft
        hideReadLeading.isActive = onLeft
        hideReadTrailing.isActive = !onLeft
    }

    /// Shown while there are read stories to hide, or while offering to undo.
    private func updateHideReadButton() {
        let isUndo = justHidden != nil
        let hasRead = stories.keys.contains { coordinator.visitedStories.isVisited($0) }
        let visible = isUndo || hasRead
        hideReadButton.configuration?.image = UIImage(systemName: isUndo ? "arrow.uturn.backward" : "eye.slash")
        hideReadButton.accessibilityLabel = isUndo ? "Undo Hide Read Stories" : "Hide Read Stories"
        guard visible == hideReadButton.isHidden else { return }
        if visible { hideReadButton.isHidden = false }
        UIView.animate(withDuration: 0.2, animations: {
            self.hideReadButton.alpha = visible ? 1 : 0
        }, completion: { _ in
            if !visible, self.hideReadButton.alpha == 0 { self.hideReadButton.isHidden = true }
        })
    }

    private func hideReadTapped() {
        undoTimer?.invalidate()
        if let hidden = justHidden {
            justHidden = nil
            coordinator.hiddenStories.unhide(hidden)
        } else {
            let read = feedStories.map(\.id).filter { stories[$0] != nil && coordinator.visitedStories.isVisited($0) }
            guard !read.isEmpty else { return }
            coordinator.hiddenStories.hide(read)
            justHidden = read
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIAccessibility.post(notification: .announcement, argument: read.count == 1 ? "Hid 1 read story" : "Hid \(read.count) read stories")
            undoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.justHidden = nil
                    self?.updateHideReadButton()
                }
            }
        }
        show(feedStories, replacing: false, animated: true)
    }

    @objc private func colorThemeChanged() {
        topFill.color = Palette.storyBackground(at: 0)
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
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
        updateHideReadButton()
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

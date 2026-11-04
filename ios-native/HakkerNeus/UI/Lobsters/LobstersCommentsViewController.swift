import UIKit

/// A lobste.rs story with its comment tree: `CommentsViewController` for lobste.rs, read-only
/// (no voting or replying). Tapping a comment collapses its replies.
final class LobstersCommentsViewController: UIViewController, UICollectionViewDelegate, StoryTransitionDestination {
    private enum Section { case header, comments }

    private enum Item: Hashable {
        case story
        case status
        case comment(Int)
    }

    private enum LoadState {
        case loading
        case loaded
        case failed(Error)
    }

    private let id: Int
    private unowned let coordinator: AppCoordinator

    private var story: Story?
    private var storyBody: CommentBody?
    private var thread = CommentThread(comments: [])
    private var commentsByID: [Int: FlatComment] = [:]
    private var bodies: [Int: CommentBody] = [:]
    private var loadState = LoadState.loading

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let refreshControl = RefreshControl()
    private let topFill = TopFillView()
    private let offlineBanner = OfflineBanner()
    private let collapseHaptics = UIImpactFeedbackGenerator(style: .light)
    private let nextThreadButton = UIButton(type: .system)
    private var nextThreadLeading: NSLayoutConstraint!
    private var nextThreadTrailing: NSLayoutConstraint!
    private let jumpHaptics = UISelectionFeedbackGenerator()

    /// The thread, when it was already loaded before the screen was pushed.
    private var preloaded: LoadedItem?

    init(id: Int, story: Story?, coordinator: AppCoordinator, preloaded: LoadedItem? = nil) {
        self.id = id
        self.story = story
        self.coordinator = coordinator
        self.preloaded = preloaded
        super.init(nibName: nil, bundle: nil)
    }

    var transitionStoryID: Int { id }

    func transitionViews() -> (header: UIView, title: UIView, color: UIColor)? {
        guard let indexPath = dataSource.indexPath(for: .story),
              let header = collectionView.cellForItem(at: indexPath) as? StoryHeaderCell
        else { return nil }
        return (header, header.titleView, Palette.lobstersAccent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        advertiseForHandoff()
    }

    /// Lets another device (Safari on a Mac, say) carry on with this discussion.
    private func advertiseForHandoff() {
        let activity = userActivity ?? NSUserActivity(activityType: "se.lindskogen.hakkerneues.item")
        activity.title = story?.title
        activity.webpageURL = Lobsters.storyURL(id)
        activity.isEligibleForHandoff = true
        userActivity = activity
        activity.becomeCurrent()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark

        configureCollectionView()
        configureDataSource()
        applySnapshot(animated: false)

        NotificationCenter.default.addObserver(self, selector: #selector(updateTimes), name: RelativeTime.tick, object: nil)

        // Comment text is a pre-built attributed string, which doesn't follow text size changes by itself.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.applySnapshot(animated: false, reconfigureAll: true)
        }

        if let preloaded {
            // Shown in the first frame, so the screen slides in filled.
            self.preloaded = nil
            let result = preloaded.item
            coordinator.offlineItems.save(result, id: id)
            show(result, flat: result.comments.flattened(), parsed: preloaded.bodies, offlineCopyDate: nil)
        } else {
            Task { await load(forceRefresh: false) }
        }
    }

    private func configureCollectionView() {
        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.backgroundColor = Theme.Color.backgroundDark
        list.showsSeparators = false

        let layout = UICollectionViewCompositionalLayout { [unowned self] index, environment in
            let section = NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
            if dataSource.sectionIdentifier(for: index) == .comments {
                section.contentInsets.bottom = Theme.padding * 3
            }
            return section
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.indicatorStyle = .white
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "comments.list"

        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        topFill.install(in: collectionView)
        configureNextThreadButton()
        offlineBanner.install(in: view)
    }

    private func configureDataSource() {
        let storyCell = UICollectionView.CellRegistration<StoryHeaderCell, Item> { [unowned self] cell, _, _ in
            if let story {
                cell.configure(with: story, body: storyBody, score: story.score, color: Palette.lobstersAccent)
            }
            cell.onLinkTap = { [unowned self] url in coordinator.open(url) }
            cell.linkMenu = { [unowned self] url, source in coordinator.linkMenu(for: url, sourceView: source) }
        }
        let statusCell = UICollectionView.CellRegistration<StatusCell, Item> { [unowned self] cell, _, _ in
            switch loadState {
            case .loading: cell.configure(with: .loading)
            case .loaded: cell.configure(with: .noComments)
            case .failed(let error): cell.configure(with: .error(error))
            }
        }
        let commentCell = UICollectionView.CellRegistration<CommentCell, Item> { [unowned self] cell, _, item in
            guard case .comment(let id) = item, let content = content(for: id) else { return }
            cell.configure(with: content)
            cell.onLinkTap = { [unowned self] url in coordinator.open(url) }
            cell.linkMenu = { [unowned self] url, source in coordinator.linkMenu(for: url, sourceView: source) }
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .story: collectionView.dequeueConfiguredReusableCell(using: storyCell, for: indexPath, item: item)
            case .status: collectionView.dequeueConfiguredReusableCell(using: statusCell, for: indexPath, item: item)
            case .comment: collectionView.dequeueConfiguredReusableCell(using: commentCell, for: indexPath, item: item)
            }
        }
    }

    private func content(for id: Int) -> CommentCell.Content? {
        guard let flat = commentsByID[id] else { return nil }
        return CommentCell.Content(
            comment: flat.comment,
            depth: flat.depth,
            body: bodies[id] ?? CommentBody(blocks: []),
            isOP: flat.comment.author != nil && flat.comment.author == story?.author,
            isCollapsed: thread.isCollapsed(id),
            hiddenReplies: thread.replyCounts[id] ?? 0
        )
    }

    // MARK: Loading

    @objc private func refresh() {
        Task { await load(forceRefresh: true) }
    }

    private func load(forceRefresh: Bool) async {
        let update: () -> Void
        do {
            let result: StoryWithComments
            var prepared: [Int: CommentBody] = [:]
            var offlineCopyDate: Date?
            do {
                let loaded = try await coordinator.itemCache.item(id: id, forceRefresh: forceRefresh)
                result = loaded.item
                prepared = loaded.bodies
                coordinator.offlineItems.save(result, id: id)
            } catch {
                // No network: fall back to the copy saved the last time this thread loaded.
                guard let saved = coordinator.offlineItems.item(id: id) else { throw error }
                result = saved.item
                offlineCopyDate = saved.fetchedAt
            }
            let (flat, parsed) = await build(result, prepared: prepared)

            update = { [self] in
                show(result, flat: flat, parsed: parsed, offlineCopyDate: offlineCopyDate)
            }
        } catch {
            update = { [self] in
                // Keep showing what we have if a refresh fails.
                if commentsByID.isEmpty {
                    loadState = .failed(error)
                } else {
                    offlineBanner.show("Offline · couldn't refresh", hideAfter: 2.5)
                }
                applySnapshot(animated: false, reconfigureAll: true)
            }
        }
        refreshControl.endRefreshing(applying: update)
    }

    private func show(_ result: StoryWithComments, flat: [FlatComment], parsed: [Int: CommentBody], offlineCopyDate: Date?) {
        if let offlineCopyDate {
            offlineBanner.show("Offline · saved \(RelativeTime.string(from: offlineCopyDate)) ago")
        } else {
            offlineBanner.hide()
        }
        story = result.story
        storyBody = result.story.text.map { CommentBody(html: $0) }
        thread = CommentThread(comments: flat, collapsed: thread.collapsed)
        commentsByID = Dictionary(flat.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        bodies = parsed
        loadState = .loaded
        applySnapshot(animated: false, reconfigureAll: true)
    }

    /// Flattens the thread and parses the HTML of comments not in `prepared` off the main
    /// thread (big threads take a moment).
    private func build(_ result: StoryWithComments, prepared: [Int: CommentBody] = [:]) async -> (flat: [FlatComment], parsed: [Int: CommentBody]) {
        let flat = result.comments.flattened()
        let missing = flat.filter { prepared[$0.id] == nil }
        guard !missing.isEmpty else { return (flat, prepared) }
        let parsed = await Task.detached(priority: .userInitiated) {
            Dictionary(missing.map { ($0.id, CommentBody(html: $0.comment.text ?? "")) }, uniquingKeysWith: { $1 })
        }.value
        return (flat, prepared.merging(parsed) { $1 })
    }

    private func applySnapshot(animated: Bool, reconfigureAll: Bool = false, reconfiguring ids: [Item] = []) {
        // The orange header reaches up under the clock.
        topFill.color = story == nil ? nil : Palette.lobstersAccent

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if story != nil {
            snapshot.appendSections([.header])
            snapshot.appendItems([.story], toSection: .header)
        }
        snapshot.appendSections([.comments])
        let visible = thread.visible
        if case .loaded = loadState, !visible.isEmpty {
            snapshot.appendItems(visible.map { .comment($0.id) }, toSection: .comments)
        } else {
            snapshot.appendItems([.status], toSection: .comments)
        }

        let existing = Set(dataSource.snapshot().itemIdentifiers)
        let toReconfigure = reconfigureAll ? snapshot.itemIdentifiers : ids
        snapshot.reconfigureItems(toReconfigure.filter { existing.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: animated)

        let threadCount = visible.lazy.filter { $0.depth == 0 }.count
        let showsButton: Bool
        if case .loaded = loadState { showsButton = threadCount > 1 } else { showsButton = false }
        nextThreadButton.isHidden = !showsButton
        // Room to scroll the last comment out from under the button.
        collectionView.contentInset.bottom = showsButton ? 64 : 0
    }

    @objc private func updateTimes() {
        for case let cell as CommentCell in collectionView.visibleCells {
            cell.updateTime()
        }
    }

    // MARK: Next thread

    private func configureNextThreadButton() {
        var config: UIButton.Configuration
        if #available(iOS 26, *) {
            config = .glass()
        } else {
            config = .filled()
            config.baseBackgroundColor = UIColor(white: 0.25, alpha: 0.9)
        }
        config.image = UIImage(systemName: "chevron.down")
        config.preferredSymbolConfigurationForImage = .init(pointSize: 18, weight: .semibold)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        nextThreadButton.configuration = config
        nextThreadButton.accessibilityLabel = "Next thread"
        nextThreadButton.accessibilityIdentifier = "comments.nextThread"
        nextThreadButton.isHidden = true
        nextThreadButton.addTarget(self, action: #selector(jumpToNextThread), for: .touchUpInside)

        nextThreadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nextThreadButton)
        NSLayoutConstraint.activate([
            nextThreadButton.widthAnchor.constraint(equalToConstant: 52),
            nextThreadButton.heightAnchor.constraint(equalToConstant: 52),
            nextThreadButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Theme.padding),
        ])
        nextThreadLeading = nextThreadButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Theme.padding * 2)
        nextThreadTrailing = nextThreadButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Theme.padding * 2)
        placeFloatingButtons()
        NotificationCenter.default.addObserver(self, selector: #selector(placeFloatingButtons), name: AppSettings.cornerButtonSideDidChange, object: nil)
    }

    /// In the lower-left corner in Leftie Mode, like the corner button on the lists.
    @objc private func placeFloatingButtons() {
        let onLeft = coordinator.settings.cornerButtonOnLeft
        nextThreadLeading.isActive = onLeft
        nextThreadTrailing.isActive = !onLeft
    }

    /// Scrolls the next top-level comment below the top of the screen up to the top.
    @objc private func jumpToNextThread() {
        let visibleTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        let tops = thread.visible.filter { $0.depth == 0 }.compactMap { comment -> (id: Int, top: CGFloat)? in
            guard let indexPath = dataSource.indexPath(for: .comment(comment.id)),
                  let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame
            else { return nil }
            return (comment.id, frame.minY)
        }
        guard let next = ThreadJump.next(after: visibleTop, threadTops: tops),
              let indexPath = dataSource.indexPath(for: .comment(next))
        else { return }

        jumpHaptics.selectionChanged()
        collectionView.scrollToItem(at: indexPath, at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    // MARK: Collapsing

    private func toggleCollapsed(_ id: Int) {
        thread.toggle(id)
        collapseHaptics.impactOccurred()
        applySnapshot(animated: !UIAccessibility.isReduceMotionEnabled, reconfiguring: [.comment(id)])

        // Collapsing from the middle of a long thread can leave the comment above the screen.
        guard thread.isCollapsed(id),
              let indexPath = dataSource.indexPath(for: .comment(id)),
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame,
              frame.minY < collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        else { return }
        collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .status
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .story:
            if let url = story?.url { coordinator.open(url) }
        case .comment(let id):
            toggleCollapsed(id)
        case .status, nil:
            break
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first,
              let cell = collectionView.cellForItem(at: indexPath)
        else { return nil }

        switch dataSource.itemIdentifier(for: indexPath) {
        case .story:
            guard let story else { return nil }
            return UIContextMenuConfiguration(actionProvider: { [unowned self, weak cell] _ in
                coordinator.lobstersStoryMenu(for: story, sourceView: cell ?? collectionView, includeComments: false)
            })
        case .comment(let id):
            guard let flat = commentsByID[id] else { return nil }
            return UIContextMenuConfiguration(actionProvider: { [unowned self, weak cell] _ in
                commentMenu(for: flat.comment, sourceView: cell ?? collectionView)
            })
        case .status, nil:
            return nil
        }
    }

    private func commentMenu(for comment: Comment, sourceView: UIView) -> UIMenu {
        let isCollapsed = thread.isCollapsed(comment.id)
        let replies = thread.replyCounts[comment.id] ?? 0
        let collapse = UIAction(
            title: isCollapsed ? "Expand Thread" : "Collapse Thread",
            subtitle: replies > 0 ? (replies == 1 ? "1 reply" : "\(replies) replies") : nil,
            image: UIImage(systemName: isCollapsed ? "arrow.up.and.down" : "arrow.down.and.line.horizontal.and.arrow.up")
        ) { [unowned self] _ in
            toggleCollapsed(comment.id)
        }

        let body = bodies[comment.id]?.plainText ?? ""
        let copyText = UIAction(title: "Copy Text", image: UIImage(systemName: "doc.on.doc")) { _ in
            UIPasteboard.general.string = body
        }
        let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [unowned self, weak sourceView] _ in
            guard let sourceView else { return }
            coordinator.share(Lobsters.commentURL(comment.id), from: sourceView)
        }
        let copyLink = UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
            UIPasteboard.general.url = Lobsters.commentURL(comment.id)
        }

        var user: [UIMenuElement] = []
        if let author = comment.author {
            // Their page on lobste.rs: user pages in the app are HN's.
            user.append(UIAction(title: author, image: UIImage(systemName: "person")) { [unowned self] _ in
                coordinator.open(Lobsters.userURL(author))
            })
        }

        let isSaved = coordinator.savedComments.isSaved(comment.id)
        let save = UIAction(title: isSaved ? "Unsave" : "Save", image: UIImage(systemName: isSaved ? "heart.slash" : "heart")) { [unowned self] _ in
            if isSaved {
                coordinator.savedComments.remove(comment.id)
            } else {
                coordinator.savedComments.save(comment, storyID: story?.id, storyTitle: story?.title)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [save, collapse]),
            UIMenu(options: .displayInline, children: [share, copyText, copyLink]),
            UIMenu(options: .displayInline, children: user),
        ])
    }
}

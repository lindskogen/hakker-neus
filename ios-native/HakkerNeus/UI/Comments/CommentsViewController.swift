import UIKit

/// A story (or comment) with its comment tree (`CommentsList.tsx`).
/// Tapping a comment collapses its replies, Apollo-style.
final class CommentsViewController: UIViewController, UICollectionViewDelegate {
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
    private var thread = CommentThread(comments: [])
    private var commentsByID: [Int: FlatComment] = [:]
    private var bodies: [Int: CommentBody] = [:]
    private var loadState = LoadState.loading

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let refreshControl = RefreshControl()
    private let collapseHaptics = UIImpactFeedbackGenerator(style: .light)

    init(id: Int, story: Story?, coordinator: AppCoordinator) {
        self.id = id
        self.story = story
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
        applySnapshot(animated: false)

        NotificationCenter.default.addObserver(self, selector: #selector(updateTimes), name: RelativeTime.tick, object: nil)

        Task { await load(forceRefresh: false) }
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
    }

    private func configureDataSource() {
        let storyCell = UICollectionView.CellRegistration<StoryHeaderCell, Item> { [unowned self] cell, _, _ in
            if let story { cell.configure(with: story) }
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
            let result = try await coordinator.itemCache.item(id: id, forceRefresh: forceRefresh)
            let flat = result.comments.flattened()
            // Parsing every comment's HTML can take a moment on big threads; keep it off the main thread.
            let parsed = await Task.detached(priority: .userInitiated) {
                Dictionary(flat.map { ($0.id, CommentBody(html: $0.comment.text ?? "")) }, uniquingKeysWith: { $1 })
            }.value

            update = { [self] in
                story = result.story
                thread = CommentThread(comments: flat, collapsed: thread.collapsed)
                commentsByID = Dictionary(flat.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
                bodies = parsed
                loadState = .loaded
                applySnapshot(animated: false, reconfigureAll: true)
            }
        } catch {
            update = { [self] in
                // Keep showing what we have if a refresh fails.
                if commentsByID.isEmpty { loadState = .failed(error) }
                applySnapshot(animated: false, reconfigureAll: true)
            }
        }
        refreshControl.endRefreshing(applying: update)
    }

    private func applySnapshot(animated: Bool, reconfigureAll: Bool = false, reconfiguring ids: [Item] = []) {
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
    }

    @objc private func updateTimes() {
        for case let cell as CommentCell in collectionView.visibleCells {
            cell.updateTime()
        }
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
                coordinator.storyMenu(for: story, sourceView: cell ?? collectionView, includeComments: false)
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
            coordinator.share(comment.hackerNewsURL, from: sourceView)
        }
        let copyLink = UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
            UIPasteboard.general.url = comment.hackerNewsURL
        }

        var user: [UIMenuElement] = []
        if let author = comment.author {
            user.append(UIAction(title: author, image: UIImage(systemName: "person")) { [unowned self] _ in
                coordinator.showUser(author)
            })
        }

        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [collapse]),
            UIMenu(options: .displayInline, children: [share, copyText, copyLink]),
            UIMenu(options: .displayInline, children: user),
        ])
    }
}

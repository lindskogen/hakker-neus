import UIKit

/// An HN user's page: karma, when they joined and their about text, then their recent stories
/// or comments, newest first, loading more as you scroll. Stories are rows like on the front
/// page; a comment opens its thread, focused on it.
final class UserViewController: UIViewController, UICollectionViewDelegate, StoryTransitionSource {
    private enum Section { case profile, activity }

    private enum Item: Hashable {
        case profile
        case story(Int)
        case comment(Int)
        case empty
    }

    enum Tab: Int, CaseIterable {
        case stories, comments

        var title: String {
            switch self {
            case .stories: "Stories"
            case .comments: "Comments"
            }
        }
    }

    let username: String
    private unowned let coordinator: AppCoordinator
    private let api: UserAPI

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let stateView = FullPageStateView()
    private let topFill = TopFillView()
    private weak var footer: LoadingFooterView?

    private var user: HNUser?
    private var about: CommentBody?
    private var selectedTab = Tab.stories
    private var stories: [Story] = []
    private var storiesByID: [Int: Story] = [:]
    private var comments: [UserComment] = []
    private var commentsByID: [Int: UserComment] = [:]
    private var commentBodies: [Int: CommentBody] = [:]
    /// Next page to load per tab, and whether there is one.
    private var nextPage: [Tab: Int] = [:]
    private var hasMore: [Tab: Bool] = [:]
    private var loadTask: Task<Void, Never>?

    init(username: String, coordinator: AppCoordinator, api: UserAPI) {
        self.username = username
        self.coordinator = coordinator
        self.api = api
        super.init(nibName: nil, bundle: nil)
        title = username
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark

        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.backgroundColor = .clear
        list.separatorConfiguration.color = .black
        list.separatorConfiguration.bottomSeparatorInsets = .zero
        let layout = UICollectionViewCompositionalLayout { index, environment in
            // Only the activity list (section 1) has the loading footer.
            var list = list
            list.footerMode = index == 1 ? .supplementary : .none
            let section = NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
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
        collectionView.accessibilityIdentifier = "user.list"
        view.addSubview(collectionView)
        topFill.install(in: collectionView)
        topFill.color = Theme.Color.backgroundDark
        collectionView.backgroundView = stateView

        configureDataSource()
        for name in [SavedStoriesStore.didChange, VisitedStoriesStore.didChange, HNSession.votesChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(storyStateChanged(_:)), name: name, object: nil)
        }
        load()
    }

    private func configureDataSource() {
        let profile = UICollectionView.CellRegistration<UserProfileCell, Item> { [unowned self] cell, _, _ in
            guard let user else { return }
            cell.configure(user: user, about: about, tab: selectedTab)
            cell.onTab = { [unowned self] in select($0) }
            cell.onLinkTap = { [unowned self] in coordinator.open($0) }
            cell.linkMenu = { [unowned self] url, source in coordinator.linkMenu(for: url, sourceView: source) }
        }
        let story = UICollectionView.CellRegistration<StoryCell, Item> { [unowned self] cell, indexPath, item in
            guard case .story(let id) = item, let story = storiesByID[id] else { return }
            coordinator.configure(cell, with: story, backgroundColor: Palette.storyBackground(at: indexPath.item), inSavedList: false)
        }
        let comment = UICollectionView.CellRegistration<UserCommentCell, Item> { [unowned self] cell, _, item in
            guard case .comment(let id) = item, let comment = commentsByID[id] else { return }
            cell.configure(with: comment, body: commentBodies[id] ?? CommentBody(html: comment.text))
            cell.onLinkTap = { [unowned self] in coordinator.open($0) }
            cell.linkMenu = { [unowned self] url, source in coordinator.linkMenu(for: url, sourceView: source) }
        }
        let empty = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [unowned self] cell, _, _ in
            var content = cell.defaultContentConfiguration()
            content.text = selectedTab == .stories ? "No stories" : "No comments"
            content.textProperties.font = Theme.Font.light(size: 24)
            content.textProperties.color = UIColor.white.withAlphaComponent(0.3)
            content.textProperties.alignment = .center
            content.directionalLayoutMargins = .init(top: 60, leading: 20, bottom: 60, trailing: 20)
            cell.contentConfiguration = content
            var background = UIBackgroundConfiguration.listPlainCell()
            background.backgroundColor = .clear
            cell.backgroundConfiguration = background
        }
        let footer = UICollectionView.SupplementaryRegistration<LoadingFooterView>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [unowned self] view, _, indexPath in
            self.footer = view
            view.isLoading = loadTask != nil
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .profile: collectionView.dequeueConfiguredReusableCell(using: profile, for: indexPath, item: item)
            case .story: collectionView.dequeueConfiguredReusableCell(using: story, for: indexPath, item: item)
            case .comment: collectionView.dequeueConfiguredReusableCell(using: comment, for: indexPath, item: item)
            case .empty: collectionView.dequeueConfiguredReusableCell(using: empty, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath)
        }
    }

    // MARK: Loading

    private func load() {
        stateView.state = .loading
        Task {
            do {
                let user = try await api.user(username)
                self.user = user
                about = user.about.map { CommentBody(html: $0) }
                collectionView.backgroundView = nil
                apply()
                loadMore()
            } catch {
                stateView.state = .error(error)
            }
        }
    }

    private func loadMore() {
        let tab = selectedTab
        guard loadTask == nil, hasMore[tab] ?? true else { return }
        let page = nextPage[tab] ?? 0
        let task = Task { [weak self, api, username] in
            defer {
                self?.loadTask = nil
                self?.footer?.isLoading = false
            }
            do {
                switch tab {
                case .stories:
                    let result = try await api.stories(by: username, page: page)
                    guard let self else { return }
                    let new = result.items.filter { self.storiesByID[$0.id] == nil }
                    stories += new
                    for story in new { storiesByID[story.id] = story }
                    hasMore[tab] = result.hasMore
                case .comments:
                    let result = try await api.comments(by: username, page: page)
                    // Parsing the HTML off the main thread, as the comments screen does.
                    let bodies = await Task.detached { Dictionary(result.items.map { ($0.id, CommentBody(html: $0.text)) }, uniquingKeysWith: { $1 }) }.value
                    guard let self else { return }
                    let new = result.items.filter { self.commentsByID[$0.id] == nil }
                    comments += new
                    for comment in new { commentsByID[comment.id] = comment }
                    commentBodies.merge(bodies) { $1 }
                    hasMore[tab] = result.hasMore
                }
                guard let self else { return }
                nextPage[tab] = page + 1
                if self.selectedTab == tab { apply() }
            } catch {
                // Scrolling to the end again retries.
            }
        }
        loadTask = task
        footer?.isLoading = true
    }

    private func apply() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.profile, .activity])
        snapshot.appendItems([.profile], toSection: .profile)
        let items: [Item] = switch selectedTab {
        case .stories: stories.map { .story($0.id) }
        case .comments: comments.map { .comment($0.id) }
        }
        let loaded = nextPage[selectedTab] != nil
        snapshot.appendItems(items.isEmpty && loaded && hasMore[selectedTab] == false ? [.empty] : items, toSection: .activity)
        // Story row colours depend on position.
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { dataSource.indexPath(for: $0) != nil })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func select(_ tab: Tab) {
        guard tab != selectedTab else { return }
        loadTask?.cancel()
        loadTask = nil
        selectedTab = tab
        apply()
        loadMore()
    }

    @objc private func storyStateChanged(_ notification: Notification) {
        var snapshot = dataSource.snapshot()
        let ids = (notification.object as? Int).map { [Item.story($0)] } ?? snapshot.itemIdentifiers
        let present = ids.filter { snapshot.indexOfItem($0) != nil }
        guard !present.isEmpty else { return }
        snapshot.reconfigureItems(present)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: Transition into comments

    func transitionViews(forStory id: Int) -> (card: UIView, title: UIView)? {
        guard let indexPath = dataSource.indexPath(for: .story(id)) else { return nil }
        return (collectionView.cellForItem(at: indexPath) as? StoryCell)?.transitionViews
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        let count = collectionView.numberOfItems(inSection: indexPath.section)
        if dataSource.sectionIdentifier(for: indexPath.section) == .activity, indexPath.item >= count - 5 {
            loadMore()
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .story, .comment: true
        default: false
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .story(let id):
            if let story = storiesByID[id] { coordinator.select(story) }
        case .comment(let id):
            // The comments screen finds the comment's story and scrolls to it.
            coordinator.showComments(id: id)
        default:
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
        case .story(let id):
            guard let story = storiesByID[id] else { return nil }
            return coordinator.contextMenuConfiguration(for: story, sourceView: cell)
        case .comment(let id):
            guard let comment = commentsByID[id] else { return nil }
            return UIContextMenuConfiguration(actionProvider: { [unowned self, weak cell] _ in
                let url = URL.hackerNewsItem(comment.id)
                let open = UIAction(title: "Open Thread", image: UIImage(systemName: "bubble.left.and.bubble.right")) { [unowned self] _ in
                    coordinator.showComments(id: comment.id)
                }
                let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [unowned self] _ in
                    coordinator.share(url, from: cell ?? collectionView)
                }
                let copyText = UIAction(title: "Copy Text", image: UIImage(systemName: "doc.on.doc")) { [unowned self] _ in
                    UIPasteboard.general.string = (commentBodies[comment.id] ?? CommentBody(html: comment.text)).plainText
                }
                let copyLink = UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
                    UIPasteboard.general.url = url
                }
                return UIMenu(children: [
                    UIMenu(options: .displayInline, children: [open]),
                    UIMenu(options: .displayInline, children: [share, copyText, copyLink]),
                ])
            })
        default:
            return nil
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        coordinator.commitContextMenuPreview(animator)
    }
}

/// The top of a user page: name, karma and age, the about text, and Stories / Comments.
final class UserProfileCell: UICollectionViewListCell {
    var onTab: ((UserViewController.Tab) -> Void)?
    var onLinkTap: ((URL) -> Void)? {
        get { aboutView.onLinkTap }
        set { aboutView.onLinkTap = newValue }
    }
    var linkMenu: ((URL, UIView) -> UIMenu)? {
        get { aboutView.linkMenu }
        set { aboutView.linkMenu = newValue }
    }

    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let aboutView = CommentBodyView()
    private let tabs = UISegmentedControl(items: UserViewController.Tab.allCases.map(\.title))

    override init(frame: CGRect) {
        super.init(frame: frame)
        var background = UIBackgroundConfiguration.listPlainCell()
        background.backgroundColor = Theme.Color.backgroundDark
        backgroundConfiguration = background

        nameLabel.font = Theme.Font.title(isPad: false)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .white
        nameLabel.numberOfLines = 0
        nameLabel.accessibilityTraits = .header

        detailLabel.font = Theme.Font.body(size: 14, style: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        detailLabel.numberOfLines = 0

        tabs.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.25)
        tabs.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        tabs.addAction(UIAction { [unowned self] _ in
            UserViewController.Tab(rawValue: tabs.selectedSegmentIndex).map { onTab?($0) }
        }, for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [nameLabel, detailLabel, aboutView, tabs])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(Theme.padding * 1.5, after: detailLabel)
        stack.setCustomSpacing(Theme.padding * 2, after: aboutView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        let padding = Theme.padding
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding * 2),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding * 1.5),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(user: HNUser, about: CommentBody?, tab: UserViewController.Tab) {
        nameLabel.text = user.id
        let karma = user.karma.formatted()
        let joined = user.created.formatted(.dateTime.month(.wide).year())
        detailLabel.text = "\(karma) karma · joined \(joined)"
        if let about, !about.blocks.isEmpty {
            aboutView.configure(with: about)
            aboutView.isHidden = false
        } else {
            aboutView.isHidden = true
        }
        tabs.selectedSegmentIndex = tab.rawValue
    }
}

/// A comment on a user page: which story it's on, the text, and how long ago.
final class UserCommentCell: UICollectionViewListCell {
    var onLinkTap: ((URL) -> Void)? {
        get { bodyView.onLinkTap }
        set { bodyView.onLinkTap = newValue }
    }
    var linkMenu: ((URL, UIView) -> UIMenu)? {
        get { bodyView.linkMenu }
        set { bodyView.linkMenu = newValue }
    }

    private let storyLabel = UILabel()
    private let timeLabel = UILabel()
    private let bodyView = CommentBodyView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        var background = UIBackgroundConfiguration.listPlainCell()
        background.backgroundColor = Theme.Color.backgroundDark
        backgroundConfiguration = background

        storyLabel.font = Theme.Font.medium(size: 13)
        storyLabel.adjustsFontForContentSizeCategory = true
        storyLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        storyLabel.numberOfLines = 2

        timeLabel.font = Theme.Font.body(size: 13, style: .footnote)
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.textColor = UIColor.white.withAlphaComponent(0.4)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [storyLabel, timeLabel])
        header.spacing = Theme.padding
        header.alignment = .firstBaseline

        let stack = UIStackView(arrangedSubviews: [header, bodyView])
        stack.axis = .vertical
        stack.spacing = Theme.padding
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        let padding = Theme.padding
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding * 1.5),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding * 1.5),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding * 1.5),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding * 1.5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with comment: UserComment, body: CommentBody) {
        storyLabel.text = comment.storyTitle.map { "on \($0)" } ?? "Comment"
        timeLabel.text = RelativeTime.string(from: comment.time)
        bodyView.configure(with: body)
        accessibilityHint = "Opens the thread"
    }
}

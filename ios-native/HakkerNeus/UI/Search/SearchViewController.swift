import UIKit

/// Story search through HN Search by Algolia: a search field, Relevant / Newest tabs, and the
/// results as quiet rows like on user pages. Kept alive by the coordinator, so going back and
/// returning keeps the query and results.
final class SearchViewController: UIViewController, UICollectionViewDelegate, UISearchTextFieldDelegate {
    enum Order: Int, TextTab {
        case relevance, date

        var title: String {
            switch self {
            case .relevance: "Relevant"
            case .date: "Newest"
            }
        }
    }

    private unowned let coordinator: AppCoordinator
    private let api: UserAPI

    private let backButton = UIButton(type: .system)
    private let searchField = UISearchTextField()
    private let tabs = TextTabsView<Order>()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Story.ID>!
    private let stateView = FullPageStateView()
    private weak var footer: LoadingFooterView?

    private var order = Order.relevance
    private var query = ""
    private var stories: [Story] = []
    private var storiesByID: [Int: Story] = [:]
    private var nextPage = 0
    private var hasMore = false
    private var searchTask: Task<Void, Never>?

    init(coordinator: AppCoordinator, api: UserAPI) {
        self.coordinator = coordinator
        self.api = api
        super.init(nibName: nil, bundle: nil)
        title = "Search"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark
        configureHeader()
        configureCollectionView()
        configureDataSource()
        for name in [SavedStoriesStore.didChange, VisitedStoriesStore.didChange, HNSession.votesChanged, SplitViewController.activeStoryDidChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(storyStateChanged(_:)), name: name, object: nil)
        }
        showHint()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if query.isEmpty { searchField.becomeFirstResponder() }
    }

    private func configureHeader() {
        searchField.placeholder = "Search Hacker News"
        searchField.font = Theme.Font.body(size: 17)
        searchField.adjustsFontForContentSizeCategory = true
        searchField.textColor = .white
        searchField.tintColor = Theme.Color.accent
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.delegate = self
        searchField.accessibilityIdentifier = "search.field"
        searchField.addAction(UIAction { [unowned self] _ in queryChanged(debounce: true) }, for: .editingChanged)

        backButton.setImage(UIImage(systemName: "chevron.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        backButton.tintColor = .white
        backButton.accessibilityLabel = "Back"
        backButton.accessibilityIdentifier = "search.back"
        backButton.addAction(UIAction { [unowned self] _ in
            searchField.resignFirstResponder()
            navigationController?.popViewController(animated: true)
        }, for: .touchUpInside)

        tabs.onSelect = { [unowned self] order in
            self.order = order
            queryChanged(debounce: false)
        }

        for view in [backButton, searchField, tabs] {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(view)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: Theme.padding / 2),
            backButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            searchField.topAnchor.constraint(equalTo: guide.topAnchor, constant: Theme.padding),
            searchField.leadingAnchor.constraint(equalTo: backButton.trailingAnchor),
            searchField.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -Theme.padding),
            searchField.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            tabs.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Theme.padding / 2),
            tabs.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
        ])
    }

    private func configureCollectionView() {
        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.backgroundColor = .clear
        list.separatorConfiguration.color = .black
        list.separatorConfiguration.bottomSeparatorInsets = .zero
        list.footerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: list)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = Theme.Color.backgroundDark
        collectionView.indicatorStyle = .white
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "search.list"
        collectionView.backgroundView = stateView
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        let story = UICollectionView.CellRegistration<StoryCell, Story.ID> { [unowned self] cell, _, id in
            guard let story = storiesByID[id] else { return }
            coordinator.configure(cell, with: story, backgroundColor: Theme.Color.backgroundDark, inSavedList: false, compact: true, openedFrom: .list)
        }
        let footer = UICollectionView.SupplementaryRegistration<LoadingFooterView>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [unowned self] view, _, _ in
            self.footer = view
            view.isLoading = searchTask != nil && !stories.isEmpty
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: story, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath)
        }
    }

    // MARK: Searching

    /// Fills in the search field and searches.
    func search(for text: String) {
        searchField.text = text
        queryChanged(debounce: false)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        queryChanged(debounce: false)
        return true
    }

    /// Searches again for what's typed, after a pause in typing (`debounce`) or straight away.
    private func queryChanged(debounce: Bool) {
        let text = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        searchTask = nil
        query = text
        guard !text.isEmpty else {
            show([], hasMore: false, replacing: true)
            showHint()
            return
        }
        if stories.isEmpty {
            stateView.state = .loading
            collectionView.backgroundView = stateView
        }
        let order = order
        searchTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            do {
                let page = try await api.searchStories(text, order: order == .date ? .date : .relevance, page: 0)
                guard !Task.isCancelled else { return }
                searchTask = nil
                nextPage = 1
                show(page.items, hasMore: page.hasMore, replacing: true)
                if page.items.isEmpty {
                    stateView.state = .message(systemImage: "magnifyingglass", text: "No stories match “\(text)”.")
                    collectionView.backgroundView = stateView
                }
            } catch {
                guard !Task.isCancelled else { return }
                searchTask = nil
                show([], hasMore: false, replacing: true)
                stateView.state = .error(error)
                collectionView.backgroundView = stateView
            }
        }
    }

    private func loadMore() {
        guard searchTask == nil, hasMore, !query.isEmpty else { return }
        let (text, order, page) = (query, order, nextPage)
        searchTask = Task {
            defer { searchTask = nil; footer?.isLoading = false }
            footer?.isLoading = true
            // A failed page is retried the next time the end of the list scrolls into view.
            guard let result = try? await api.searchStories(text, order: order == .date ? .date : .relevance, page: page),
                  !Task.isCancelled
            else { return }
            nextPage = page + 1
            show(stories + result.items, hasMore: result.hasMore, replacing: false)
        }
    }

    private func show(_ all: [Story], hasMore: Bool, replacing: Bool) {
        self.hasMore = hasMore
        // Algolia can list a story on two pages when new ones arrive between requests.
        var seen = Set<Int>()
        stories = all.filter { seen.insert($0.id).inserted }
        storiesByID = Dictionary(stories.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        if !stories.isEmpty { collectionView.backgroundView = nil }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Story.ID>()
        snapshot.appendSections([0])
        snapshot.appendItems(stories.map(\.id))
        if replacing {
            snapshot.reconfigureItems(stories.map(\.id).filter(dataSource.snapshot().itemIdentifiers.contains))
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        if replacing, !stories.isEmpty {
            collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
        }
    }

    private func showHint() {
        stateView.state = .message(systemImage: "magnifyingglass", text: "Search stories on Hacker News.")
        collectionView.backgroundView = stateView
    }

    @objc private func storyStateChanged(_ notification: Notification) {
        var snapshot = dataSource.snapshot()
        if let id = notification.object as? Int {
            guard snapshot.indexOfItem(id) != nil else { return }
            snapshot.reconfigureItems([id])
        } else {
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item >= stories.count - 5 { loadMore() }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let story = storiesByID[id] else { return }
        coordinator.select(story)
    }

    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        dataSource.itemIdentifier(for: indexPath).flatMap { storiesByID[$0] }.map(coordinator.prefetchComments)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first,
              let cell = collectionView.cellForItem(at: indexPath),
              let story = dataSource.itemIdentifier(for: indexPath).flatMap({ storiesByID[$0] })
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

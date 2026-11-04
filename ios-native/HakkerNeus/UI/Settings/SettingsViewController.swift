import UIKit
import UniformTypeIdentifiers

/// Settings, shown as a sheet from the saved list.
final class SettingsViewController: UITableViewController, UIDocumentPickerDelegate {
    private enum Row {
        case account
        case signIn
        case signOut
        case importCSV
        case exportCSV
        case readerMode
        case theme(ColorTheme)
        case codeWrap
        case codeSize
        case leftHanded
        case newMinimumScore
        case adBlocking
        case linkBrowser
    }

    private struct Section {
        let title: String?
        let footer: String?
        let rows: [Row]
    }

    private unowned let coordinator: AppCoordinator

    private var sections: [Section] {
        let count = coordinator.savedStories.allEntries.count
        let session = coordinator.session
        return [
            Section(
                title: "Hacker News Account",
                footer: session.isSignedIn ? nil : "Sign in to vote and comment.",
                rows: session.isSignedIn ? [.account, .signOut] : [.signIn]
            ),
            Section(
                title: "Saved Stories",
                footer: "\(count) saved. Uses the same CSV format as hacker-feed's bookmarks export.",
                rows: [.importCSV, .exportCSV]
            ),
            Section(title: "Appearance", footer: "The colours of the front page and the saved stories.", rows: ColorTheme.allCases.map(Row.theme)),
            Section(title: "Front Page Button", footer: "Puts the button in the lower-left corner instead of the lower-right.", rows: [.leftHanded]),
            Section(title: "New Stories", footer: "Hides stories in the New list with fewer points than this.", rows: [.newMinimumScore]),
            Section(title: "Comments", footer: "Text size applies to comments and post text, code included. Unwrapped code scrolls sideways.", rows: [.codeSize, .codeWrap]),
            coordinator.settings.opensLinksInSafari
                ? Section(
                    title: "Links",
                    footer: "Safari keeps your logins and opens articles in Reader mode when the page supports it. Beside the list on iPad, articles use the built-in browser.",
                    rows: [.linkBrowser, .readerMode]
                )
                : Section(
                    title: "Links",
                    footer: "The built-in browser blocks ads. Safari keeps your logins and has Reader mode.",
                    rows: [.linkBrowser]
                ),
            Section(
                title: "Ad Blocking",
                footer: "The built-in browser always blocks ads. To block them in Safari too, turn on HackerNeus in the Settings app under Apps › Safari › Extensions. Uses EasyList by The EasyList authors (easylist.to), CC BY-SA.",
                rows: [.adBlocking]
            ),
        ]
    }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(style: .insetGrouped)
        title = "Settings"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        NotificationCenter.default.addObserver(self, selector: #selector(sessionChanged), name: HNSession.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAdBlockingState), name: UIApplication.didBecomeActiveNotification, object: nil)
        refreshAdBlockingState()
    }

    /// Whether the content blocker is on, checked again on coming back from the Settings app.
    private var adBlockingEnabled: Bool?

    @objc private func refreshAdBlockingState() {
        Task {
            adBlockingEnabled = await AdBlocking.isExtensionEnabled()
            guard let index = sections.firstIndex(where: { $0.rows.contains { if case .adBlocking = $0 { true } else { false } } }) else { return }
            tableView.reloadSections(IndexSet(integer: index), with: .none)
        }
    }

    @objc private func sessionChanged() {
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section].footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch sections[indexPath.section].rows[indexPath.row] {
        case .account:
            content.text = coordinator.session.username
            content.secondaryText = "Signed in"
            content.image = UIImage(systemName: "person.crop.circle.fill")
            cell.selectionStyle = .none
        case .signIn:
            content.text = "Sign In…"
            content.image = UIImage(systemName: "person.crop.circle")
            content.textProperties.color = .tintColor
        case .signOut:
            content.text = "Sign Out"
            content.textProperties.color = .systemRed
        case .importCSV:
            content.text = "Import from CSV…"
            content.image = UIImage(systemName: "square.and.arrow.down")
        case .exportCSV:
            content.text = "Export to CSV…"
            content.image = UIImage(systemName: "square.and.arrow.up")
        case .readerMode:
            content.text = "Open in Reader Mode"
            let toggle = UISwitch()
            toggle.isOn = coordinator.settings.opensLinksInReaderMode
            toggle.accessibilityIdentifier = "settings.readerMode"
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                self?.coordinator.settings.opensLinksInReaderMode = toggle?.isOn ?? false
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .linkBrowser:
            content.text = "Open In"
            let picker = UISegmentedControl(items: ["Built-in", "Safari"])
            picker.selectedSegmentIndex = coordinator.settings.opensLinksInSafari ? 1 : 0
            picker.accessibilityIdentifier = "settings.linkBrowser"
            picker.addAction(UIAction { [weak self, weak picker] _ in
                guard let self, let picker else { return }
                coordinator.settings.opensLinksInSafari = picker.selectedSegmentIndex == 1
                if !coordinator.settings.opensLinksInSafari { AdBlocking.prepare() }
                tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
            }, for: .valueChanged)
            picker.sizeToFit()
            cell.accessoryView = picker
            cell.selectionStyle = .none
        case .adBlocking:
            content.text = "Block Ads in Safari"
            content.secondaryText = adBlockingEnabled.map { $0 ? "On" : "Off" }
            content.prefersSideBySideTextAndSecondaryText = true
            cell.selectionStyle = .none
        case .theme(let theme):
            content.text = theme.title
            content.image = UIImage(systemName: "circle.fill")
            content.imageProperties.tintColor = Palette.accent(theme: theme)
            cell.accessoryType = theme == coordinator.settings.colorTheme ? .checkmark : .none
        case .codeWrap:
            content.text = "Wrap Code Lines"
            let toggle = UISwitch()
            toggle.isOn = coordinator.settings.commentTextStyle.wrapsLines
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                self?.coordinator.settings.commentTextStyle.wrapsLines = toggle?.isOn ?? false
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .leftHanded:
            content.text = "Leftie Mode"
            let toggle = UISwitch()
            toggle.isOn = coordinator.settings.cornerButtonOnLeft
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                self?.coordinator.settings.cornerButtonOnLeft = toggle?.isOn ?? false
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .newMinimumScore:
            content.text = "Minimum Votes"
            let options = AppSettings.newMinimumScoreOptions
            let picker = UISegmentedControl(items: options.map { $0 == 0 ? "Any" : "\($0)" })
            picker.selectedSegmentIndex = options.firstIndex(of: coordinator.settings.newMinimumScore) ?? 0
            picker.addAction(UIAction { [weak self, weak picker] _ in
                guard let index = picker?.selectedSegmentIndex, options.indices.contains(index) else { return }
                self?.coordinator.settings.newMinimumScore = options[index]
            }, for: .valueChanged)
            picker.sizeToFit()
            cell.accessoryView = picker
            cell.selectionStyle = .none
        case .codeSize:
            content.text = "Text Size"
            let sizes = CommentTextStyle.Size.allCases
            let picker = UISegmentedControl(items: sizes.map(\.title))
            picker.selectedSegmentIndex = sizes.firstIndex(of: coordinator.settings.commentTextStyle.size) ?? 1
            picker.addAction(UIAction { [weak self, weak picker] _ in
                guard let index = picker?.selectedSegmentIndex, sizes.indices.contains(index) else { return }
                self?.coordinator.settings.commentTextStyle.size = sizes[index]
            }, for: .valueChanged)
            // Accessory views are laid out by frame, not Auto Layout.
            picker.sizeToFit()
            cell.accessoryView = picker
            cell.selectionStyle = .none
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .account:
            break
        case .signIn:
            coordinator.showSignIn()
        case .signOut:
            let confirm = UIAlertController(title: "Sign out of \(coordinator.session.username ?? "Hacker News")?", message: nil, preferredStyle: .actionSheet)
            confirm.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in
                self?.coordinator.session.signOut()
            })
            confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            confirm.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            present(confirm, animated: true)
        case .importCSV:
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.commaSeparatedText, .plainText], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        case .exportCSV:
            exportCSV(from: tableView.cellForRow(at: indexPath) ?? tableView)
        case .readerMode, .codeWrap, .codeSize, .leftHanded, .newMinimumScore, .adBlocking, .linkBrowser:
            break
        case .theme(let theme):
            coordinator.settings.colorTheme = theme
            // The home screen icon follows; iOS confirms the change with an alert of its own.
            if UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != theme.alternateIconName {
                UIApplication.shared.setAlternateIconName(theme.alternateIconName)
            }
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        }
    }

    // MARK: Import and export

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let result = BookmarksCSV.read(text)
            let (added, alreadySaved) = try coordinator.savedStories.merge(result.entries)
            var lines = ["Imported \(added) \(added == 1 ? "story" : "stories")."]
            if alreadySaved > 0 { lines.append("\(alreadySaved) already saved.") }
            if result.skipped > 0 { lines.append("Skipped \(result.skipped) unreadable \(result.skipped == 1 ? "row" : "rows").") }
            showAlert(title: "Import Finished", message: lines.joined(separator: " "))
            tableView.reloadData()
        } catch {
            showAlert(title: "Couldn't Import", message: error.localizedDescription)
        }
    }

    private func exportCSV(from sourceView: UIView) {
        let csv = BookmarksCSV.write(coordinator.savedStories.allEntries)
        let url = FileManager.default.temporaryDirectory.appending(path: "hakkerneus_bookmarks.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showAlert(title: "Couldn't Export", message: error.localizedDescription)
            return
        }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = sourceView
        present(share, animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

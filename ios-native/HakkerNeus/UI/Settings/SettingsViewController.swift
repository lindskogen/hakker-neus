import UIKit

/// Settings, shown as a sheet from the saved list.
final class SettingsViewController: UITableViewController {
    private enum Row {
        case readerMode
    }

    private struct Section {
        let title: String?
        let footer: String?
        let rows: [Row]
    }

    private unowned let coordinator: AppCoordinator

    private var sections: [Section] {
        [
            Section(
                title: "Links",
                footer: "Articles open in Reader mode when the page supports it.",
                rows: [.readerMode]
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
        cell.selectionStyle = .default

        switch sections[indexPath.section].rows[indexPath.row] {
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
        }
        cell.contentConfiguration = content
        return cell
    }
}

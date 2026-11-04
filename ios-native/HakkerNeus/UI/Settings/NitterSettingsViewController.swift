import UIKit

/// Settings › Links › X Links: whether x.com links open through Nitter, and which instances
/// back up xcancel.com (the suggested ones and any the user adds).
final class NitterSettingsViewController: UITableViewController {
    private enum Row {
        case enabled
        case primary
        case fallback(String)
        case add
    }

    private struct Section {
        let title: String?
        let footer: String?
        let rows: [Row]
    }

    private unowned let coordinator: AppCoordinator
    private var settings: AppSettings { coordinator.settings }

    /// Suggested and added instances, the order fallbacks are tried in.
    private var knownInstances: [String] {
        var seen = Set<String>()
        return (NitterRedirect.suggestedFallbacks + settings.customNitterInstances + settings.nitterFallbacks)
            .filter { seen.insert($0).inserted }
    }

    private var sections: [Section] {
        var sections = [Section(
            title: nil,
            footer: "Opens posts on x.com and twitter.com through Nitter, which shows them without an X account. "
                + "Turn off to open them on X.",
            rows: [.enabled]
        )]
        guard settings.opensXLinksViaNitter else { return sections }
        sections.append(Section(title: "Primary", footer: nil, rows: [.primary]))
        sections.append(Section(
            title: "Fallbacks",
            footer: "Tried in order when the one before is down; with none up, links open on X. "
                + "Nitter instances come and go, so add one you trust if these stop working.",
            rows: knownInstances.map(Row.fallback) + [.add]
        ))
        return sections
    }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(style: .insetGrouped)
        title = "X Links"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
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
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch sections[indexPath.section].rows[indexPath.row] {
        case .enabled:
            content.text = "Open via Nitter"
            let toggle = UISwitch()
            toggle.isOn = settings.opensXLinksViaNitter
            toggle.accessibilityIdentifier = "settings.nitter"
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let self else { return }
                settings.opensXLinksViaNitter = toggle?.isOn ?? true
                coordinator.nitter.invalidate()
                coordinator.nitter.prepare()
                tableView.reloadData()
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .primary:
            content.text = NitterRedirect.primary
            content.secondaryText = "Tried first"
            content.prefersSideBySideTextAndSecondaryText = true
            cell.selectionStyle = .none
        case .fallback(let host):
            content.text = host
            if !NitterRedirect.suggestedFallbacks.contains(host) { content.secondaryText = "Added" }
            content.prefersSideBySideTextAndSecondaryText = true
            cell.accessoryType = settings.nitterFallbacks.contains(host) ? .checkmark : .none
        case .add:
            content.text = "Add Instance…"
            content.textProperties.color = .tintColor
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .enabled, .primary:
            break
        case .fallback(let host):
            var enabled = Set(settings.nitterFallbacks)
            if enabled.contains(host) { enabled.remove(host) } else { enabled.insert(host) }
            setFallbacks(enabled)
            tableView.reloadRows(at: [indexPath], with: .none)
        case .add:
            askForInstance()
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if case .fallback(let host) = sections[indexPath.section].rows[indexPath.row] {
            return !NitterRedirect.suggestedFallbacks.contains(host)
        }
        return false
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, case .fallback(let host) = sections[indexPath.section].rows[indexPath.row] else { return }
        settings.customNitterInstances.removeAll { $0 == host }
        setFallbacks(Set(settings.nitterFallbacks).subtracting([host]))
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    /// Saves the enabled fallbacks in the order they're listed.
    private func setFallbacks(_ enabled: Set<String>) {
        settings.nitterFallbacks = knownInstances.filter(enabled.contains)
        coordinator.nitter.invalidate()
    }

    private func askForInstance() {
        let alert = UIAlertController(title: "Add Nitter Instance", message: "Its address, like nitter.example.com.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "nitter.example.com"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self, let host = Self.host(from: alert?.textFields?.first?.text ?? "") else { return }
            if !knownInstances.contains(host) { settings.customNitterInstances.append(host) }
            setFallbacks(Set(settings.nitterFallbacks).union([host]))
            tableView.reloadData()
        })
        present(alert, animated: true)
    }

    /// The host from what was typed: a bare host or a whole URL.
    static func host(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
        guard let host = url?.host(), host.contains("."), host != NitterRedirect.primary else { return nil }
        return host
    }
}

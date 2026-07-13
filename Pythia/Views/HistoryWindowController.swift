import AppKit
import Foundation

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    var onLoadRecord: ((TranslationRecord) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pythia 历史"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 460)
        super.init(window: window)
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .historyChanged, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let title = NSTextField(labelWithString: "历史记录")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.alignment = .left
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(title)

        let columns = [
            ("date", "时间", CGFloat(150)),
            ("provider", "服务", CGFloat(90)),
            ("source", "原文", CGFloat(300)),
            ("result", "译文", CGFloat(300)),
        ]
        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.0))
            tableColumn.title = column.1
            tableColumn.width = column.2
            tableView.addTableColumn(tableColumn)
        }
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 44
        tableView.dataSource = self
        tableView.delegate = self

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = tableView
        root.addArrangedSubview(scroll)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.addArrangedSubview(PillButton("加载到翻译页", target: self, action: #selector(loadSelected)))
        buttons.addArrangedSubview(PillButton("删除选中", target: self, action: #selector(deleteSelected)))
        buttons.addArrangedSubview(PillButton("导出 JSON", target: self, action: #selector(exportHistory)))
        buttons.addArrangedSubview(NSView())
        buttons.addArrangedSubview(PillButton("清空历史", target: self, action: #selector(clearHistory)))
        root.addArrangedSubview(buttons)
    }

    func showAndFocus() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        HistoryStore.shared.records.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        cell.subviews.forEach { $0.removeFromSuperview() }
        guard row < HistoryStore.shared.records.count else { return cell }
        let record = HistoryStore.shared.records[row]
        let value: String
        switch id.rawValue {
        case "date":
            value = DateFormatter.localizedString(from: record.date, dateStyle: .short, timeStyle: .short)
        case "provider":
            value = record.provider
        case "source":
            value = record.source
        default:
            value = record.result
        }
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func reload() {
        tableView.reloadData()
        let count = HistoryStore.shared.records.count
        if count == 0 {
            tableView.deselectAll(nil)
        } else if tableView.selectedRow >= count {
            tableView.selectRowIndexes(IndexSet(integer: count - 1), byExtendingSelection: false)
        }
    }

    @objc private func loadSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < HistoryStore.shared.records.count else {
            showAlert(title: "未选择历史记录", message: "请先选择一条历史记录。")
            return
        }
        onLoadRecord?(HistoryStore.shared.records[row])
        showAlert(title: "已加载", message: "已将选中的历史记录加载到翻译窗口。")
    }

    @objc private func deleteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < HistoryStore.shared.records.count else {
            showAlert(title: "未选择历史记录", message: "请先选择要删除的历史记录。")
            return
        }
        let alert = NSAlert()
        alert.messageText = "删除选中的历史记录？"
        alert.informativeText = "这会从本机历史中删除该条记录。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        HistoryStore.shared.delete(at: row)
        showAlert(title: "已删除", message: "选中的历史记录已删除。")
    }

    @objc private func clearHistory() {
        guard !HistoryStore.shared.records.isEmpty else {
            showAlert(title: "历史为空", message: "当前没有可清空的历史记录。")
            return
        }
        let alert = NSAlert()
        alert.messageText = "清空全部历史记录？"
        alert.informativeText = "这会删除本机保存的全部翻译历史。此操作无法撤销。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        HistoryStore.shared.clear()
        showAlert(title: "已清空", message: "全部翻译历史已清空。")
    }

    @objc private func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "pythia-history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = HistoryStore.shared.records.count
            try HistoryStore.shared.export(to: url)
            showAlert(title: "导出完成", message: "已导出 \(count) 条历史记录。")
        } catch {
            showAlert(title: "导出失败", message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    private let tagStore = ID3v2AudioTagStore()

    @State private var selectedSidebarItem: SidebarItem? = .library
    @State private var importedItems: [ImportedItem] = []
    @State private var selectedItemID: ImportedItem.ID?
    @State private var searchText = ""
    @State private var isInspectorPresented = true
    @State private var isFileImporterPresented = false
    @State private var lastImportSkippedItems: [MP3ImportSkippedItem] = []

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSidebarItem)
        } detail: {
            ImportedItemTable(
                items: filteredItems,
                skippedItems: lastImportSkippedItems,
                selectedItemID: $selectedItemID,
                importAction: openFileImporter,
                updateMetadataFieldAction: { itemID, field, value in
                    updateMetadataField(itemID: itemID, field: field, value: value)
                },
                resetMetadataFieldAction: resetMetadataField,
                dismissSkippedItemsAction: { lastImportSkippedItems = [] }
            )
            .inspector(isPresented: $isInspectorPresented) {
                InspectorPlaceholder(item: selectedItem)
            }
        }
        .navigationTitle(Text(verbatim: String()))
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter files")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openFileImporter()
                } label: {
                    Label("Open", systemImage: "folder")
                }

                Button {
                    openFileImporter()
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
            }

            ToolbarItemGroup {
                Button {
                } label: {
                    Label("Review Changes", systemImage: "list.bullet.rectangle")
                }
                .disabled(true)

                Button {
                } label: {
                    Label("Save Tags", systemImage: "square.and.arrow.down")
                }
                .disabled(true)
            }

            ToolbarItem {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.mp3, .folder],
            allowsMultipleSelection: true
        ) { result in
            handleImportedURLs(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            addImportedURLs(urls)
            return !urls.isEmpty
        }
        .frame(minWidth: 700, minHeight: 360)
    }

    private var filteredItems: [ImportedItem] {
        guard !searchText.isEmpty else { return importedItems }

        return importedItems.filter { item in
            item.displayName.localizedStandardContains(searchText)
                || item.statusTitle.localizedStandardContains(searchText)
                || item.url.path.localizedStandardContains(searchText)
        }
    }

    private var selectedItem: ImportedItem? {
        importedItems.first { $0.id == selectedItemID }
    }

    private func openFileImporter() {
        isFileImporterPresented = true
    }

    private func handleImportedURLs(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        addImportedURLs(urls)
    }

    private func addImportedURLs(_ urls: [URL]) {
        let scanResult = MP3ImportScanner().scan(
            urls: urls,
            existingURLs: Set(importedItems.map(\.url))
        )
        var newItems: [ImportedItem] = []
        var metadataSkippedItems: [MP3ImportSkippedItem] = []

        for url in scanResult.acceptedURLs {
            let metadataLoadReport = loadMetadataReport(from: url)
            if metadataLoadReport.error == nil {
                newItems.append(ImportedItem(url: url, metadataLoadReport: metadataLoadReport))
            } else {
                metadataSkippedItems.append(MP3ImportSkippedItem(url: url, reason: .readError))
            }
        }

        lastImportSkippedItems = scanResult.skippedItems + metadataSkippedItems

        guard !newItems.isEmpty else { return }

        importedItems.append(contentsOf: newItems)
        selectedItemID = newItems.last?.id
    }

    private func updateMetadataField(
        itemID: ImportedItem.ID,
        field: TrackMetadataField,
        value: TrackMetadataFieldValue
    ) {
        guard let itemIndex = importedItems.firstIndex(where: { $0.id == itemID }) else { return }
        let oldValue = importedItems[itemIndex].metadataState.current.value(for: field)
        guard oldValue != value else { return }

        importedItems[itemIndex].metadataState.update(field, to: value)
    }

    private func resetMetadataField(itemID: ImportedItem.ID, field: TrackMetadataField) {
        guard let itemIndex = importedItems.firstIndex(where: { $0.id == itemID }) else { return }
        importedItems[itemIndex].metadataState.reset(field)
    }

    private func loadMetadataReport(from url: URL) -> TrackMetadataLoadReport {
        let canAccessScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if canAccessScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return tagStore.loadMetadataReport(from: url)
    }
}

private struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.title, systemImage: item.systemImage)
                .tag(item)
        }
        .navigationTitle("Liner")
        .navigationSplitViewColumnWidth(min: 150, ideal: 210, max: 260)
    }
}

private struct ImportedItemTable: View {
    let items: [ImportedItem]
    let skippedItems: [MP3ImportSkippedItem]
    @Binding var selectedItemID: ImportedItem.ID?
    let importAction: () -> Void
    let updateMetadataFieldAction: (ImportedItem.ID, TrackMetadataField, TrackMetadataFieldValue) -> Void
    let resetMetadataFieldAction: (ImportedItem.ID, TrackMetadataField) -> Void
    let dismissSkippedItemsAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !skippedItems.isEmpty {
                ImportSkippedBanner(
                    skippedItems: skippedItems,
                    dismissAction: dismissSkippedItemsAction
                )
            }

            if items.isEmpty {
                ContentUnavailableView {
                    Label("No Files Loaded", systemImage: "tray.and.arrow.down")
                } description: {
                    Text("Open MP3 files or folders, or drag them here from Finder.")
                } actions: {
                    Button(action: importAction) {
                        Label("Open MP3 Files or Folders", systemImage: "folder.badge.plus")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MetadataSpreadsheetView(
                    items: items,
                    selectedItemID: $selectedItemID,
                    updateMetadataFieldAction: updateMetadataFieldAction,
                    resetMetadataFieldAction: resetMetadataFieldAction
                )
            }

            ImportedItemFooter(itemCount: items.count)
        }
    }
}

private struct MetadataSpreadsheetView: NSViewRepresentable {
    let items: [ImportedItem]
    @Binding var selectedItemID: ImportedItem.ID?
    let updateMetadataFieldAction: (ImportedItem.ID, TrackMetadataField, TrackMetadataFieldValue) -> Void
    let resetMetadataFieldAction: (ImportedItem.ID, TrackMetadataField) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedItemID: $selectedItemID,
            updateMetadataFieldAction: updateMetadataFieldAction,
            resetMetadataFieldAction: resetMetadataFieldAction
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = MetadataTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.headerView = NSTableHeaderView()
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .none
        tableView.rowHeight = 26
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.cellSelectionChanged = { [weak coordinator = context.coordinator, weak tableView] row, column, extendsSelection in
            guard let tableView else { return }
            coordinator?.selectCell(row: row, column: column, extendsSelection: extendsSelection, in: tableView)
        }
        tableView.editFocusedCell = { [weak coordinator = context.coordinator, weak tableView] in
            guard let tableView else { return }
            coordinator?.editFocusedCell(in: tableView)
        }
        tableView.copyFocusedCell = { [weak coordinator = context.coordinator, weak tableView] in
            guard let tableView else { return nil }
            return coordinator?.copySelection(in: tableView)
        }
        tableView.pasteRows = { [weak coordinator = context.coordinator, weak tableView] rows in
            guard let tableView else { return false }
            return coordinator?.paste(rows: rows, in: tableView) ?? false
        }

        for column in MetadataSpreadsheetColumn.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.minWidth = column.minWidth
            tableColumn.width = column.defaultWidth
            tableColumn.resizingMask = .userResizingMask
            tableView.addTableColumn(tableColumn)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.items = items
        context.coordinator.selectedItemID = $selectedItemID
        context.coordinator.updateMetadataFieldAction = updateMetadataFieldAction
        context.coordinator.resetMetadataFieldAction = resetMetadataFieldAction
        tableView.reloadData()
        context.coordinator.applySelection(to: tableView)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var items: [ImportedItem] = []
        var selectedItemID: Binding<ImportedItem.ID?>
        var updateMetadataFieldAction: (ImportedItem.ID, TrackMetadataField, TrackMetadataFieldValue) -> Void
        var resetMetadataFieldAction: (ImportedItem.ID, TrackMetadataField) -> Void
        private var focusedCell: MetadataCell?
        private var selectedCellRange: MetadataCellRange?
        private var copiedCellRange: MetadataCellRange?
        private var copyFeedbackWorkItem: DispatchWorkItem?
        private var isApplyingSelection = false

        init(
            selectedItemID: Binding<ImportedItem.ID?>,
            updateMetadataFieldAction: @escaping (ImportedItem.ID, TrackMetadataField, TrackMetadataFieldValue) -> Void,
            resetMetadataFieldAction: @escaping (ImportedItem.ID, TrackMetadataField) -> Void
        ) {
            self.selectedItemID = selectedItemID
            self.updateMetadataFieldAction = updateMetadataFieldAction
            self.resetMetadataFieldAction = resetMetadataFieldAction
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard
                row < items.count,
                let identifier = tableColumn?.identifier,
                let column = MetadataSpreadsheetColumn(identifier: identifier)
            else {
                return nil
            }

            let cellView: MetadataCellView
            if let reusedView = tableView.makeView(
                withIdentifier: column.cellIdentifier,
                owner: self
            ) as? MetadataCellView {
                cellView = reusedView
            } else {
                cellView = MetadataCellView()
                cellView.identifier = column.cellIdentifier
                cellView.resetButton.target = self
                cellView.resetButton.action = #selector(resetCell(_:))
            }

            let item = items[row]
            let textField = cellView.textField
            textField.itemID = item.id
            textField.column = column
            textField.row = row
            textField.delegate = self
            textField.isEditable = column.isEditable
            textField.isSelectable = column.isEditable
            let cell = MetadataCell(row: row, column: tableView.column(withIdentifier: column.identifier))
            let visualState = MetadataCellVisualState(
                isFocused: focusedCell == cell,
                isSelected: selectedCellRange?.contains(cell) == true,
                isCopied: copiedCellRange?.contains(cell) == true
            )
            textField.stringValue = column.value(for: item)
            textField.textColor = column.textColor(for: item)
            cellView.configure(
                itemID: item.id,
                field: column.metadataField,
                row: row,
                isDirty: column.isDirty(for: item),
                visualState: visualState,
                dirtyBackgroundColor: column.backgroundColor(for: item)
            )
            return cellView
        }

        @MainActor
        @objc private func resetCell(_ sender: MetadataCellResetButton) {
            guard
                let itemID = sender.itemID,
                let metadataField = sender.metadataField,
                let row = sender.row,
                let tableView = sender.enclosingScrollView?.documentView as? NSTableView
            else {
                return
            }

            if let itemIndex = items.firstIndex(where: { $0.id == itemID }) {
                items[itemIndex].metadataState.reset(metadataField)
            }

            resetMetadataFieldAction(itemID, metadataField)
            tableView.reloadData(
                forRowIndexes: IndexSet(integer: row),
                columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
            )
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard
                let textField = notification.object as? MetadataCellTextField,
                let itemID = textField.itemID,
                let row = textField.row,
                let metadataField = textField.column?.metadataField,
                textField.column?.isEditable == true
            else {
                return
            }

            guard let tableView = textField.enclosingScrollView?.documentView as? NSTableView else { return }
            let newValue = metadataField.editedValue(from: textField.stringValue)
            if let itemIndex = items.firstIndex(where: { $0.id == itemID }) {
                let oldValue = items[itemIndex].metadataState.current.value(for: metadataField)
                if oldValue != newValue {
                    items[itemIndex].metadataState.update(metadataField, to: newValue)
                    updateMetadataFieldAction(itemID, metadataField, newValue)
                }
            } else {
                updateMetadataFieldAction(itemID, metadataField, newValue)
            }

            tableView.window?.makeFirstResponder(tableView)
            tableView.reloadData(
                forRowIndexes: IndexSet(integer: row),
                columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
            )
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard
                !isApplyingSelection,
                let tableView = notification.object as? NSTableView
            else {
                return
            }

            let selectedRow = tableView.selectedRow
            selectedItemID.wrappedValue = selectedRow >= 0 && selectedRow < items.count
                ? items[selectedRow].id
                : nil
        }

        @MainActor
        func applySelection(to tableView: NSTableView) {
            isApplyingSelection = true
            defer { isApplyingSelection = false }

            guard
                let selectedItemID = selectedItemID.wrappedValue,
                let row = items.firstIndex(where: { $0.id == selectedItemID })
            else {
                tableView.deselectAll(nil)
                return
            }

            let indexSet = IndexSet(integer: row)
            if tableView.selectedRowIndexes != indexSet {
                tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
                tableView.scrollRowToVisible(row)
            }

            if focusedCell == nil {
                selectCell(row: row, column: firstEditableColumnIndex(in: tableView), extendsSelection: false, in: tableView)
            }
        }

        @MainActor
        func selectCell(row: Int, column: Int, extendsSelection: Bool, in tableView: NSTableView) {
            guard !items.isEmpty, tableView.numberOfColumns > 0 else { return }
            let clampedRow = min(max(row, 0), items.count - 1)
            let clampedColumn = min(max(column, 0), tableView.numberOfColumns - 1)
            let oldCell = focusedCell
            let oldRange = selectedCellRange
            let newCell = MetadataCell(row: clampedRow, column: clampedColumn)
            focusedCell = newCell
            selectedCellRange = extendsSelection
                ? MetadataCellRange(anchor: selectedCellRange?.anchor ?? oldCell ?? newCell, focused: newCell)
                : nil
            selectedItemID.wrappedValue = items[clampedRow].id

            if let tableView = tableView as? MetadataTableView {
                tableView.focusedCell = focusedCell
            }

            var rowIndexes = IndexSet(integer: clampedRow)
            if let oldRow = oldCell?.row {
                rowIndexes.insert(oldRow)
            }
            if let oldRange {
                rowIndexes.formUnion(oldRange.rowIndexes)
            }
            if let selectedCellRange {
                rowIndexes.formUnion(selectedCellRange.rowIndexes)
            }

            tableView.selectRowIndexes(IndexSet(integer: clampedRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(clampedRow)
            tableView.scrollColumnToVisible(clampedColumn)
            tableView.reloadData(
                forRowIndexes: rowIndexes,
                columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
            )
        }

        @MainActor
        func editFocusedCell(in tableView: NSTableView) {
            guard
                let focusedCell,
                focusedCell.row >= 0,
                focusedCell.row < items.count,
                focusedCell.column >= 0,
                focusedCell.column < tableView.numberOfColumns,
                let column = MetadataSpreadsheetColumn(
                    identifier: tableView.tableColumns[focusedCell.column].identifier
                ),
                column.isEditable
            else {
                return
            }

            if let cellView = tableView.view(
                atColumn: focusedCell.column,
                row: focusedCell.row,
                makeIfNecessary: true
            ) as? MetadataCellView {
                tableView.window?.makeFirstResponder(cellView.textField)
                cellView.textField.selectText(nil)
            } else {
                tableView.editColumn(focusedCell.column, row: focusedCell.row, with: nil, select: true)
            }
        }

        @MainActor
        func copySelection(in tableView: NSTableView) -> String? {
            guard
                let focusedCell,
                focusedCell.row >= 0,
                focusedCell.row < items.count,
                focusedCell.column >= 0,
                focusedCell.column < tableView.numberOfColumns
            else {
                return nil
            }

            let range = selectedCellRange ?? MetadataCellRange(anchor: focusedCell, focused: focusedCell)
            let copiedText = SpreadsheetClipboard.tsv(from: range.rows.map { row in
                row.compactMap { cell in
                    guard
                        cell.row >= 0,
                        cell.row < items.count,
                        cell.column >= 0,
                        cell.column < tableView.numberOfColumns,
                        let column = MetadataSpreadsheetColumn(
                            identifier: tableView.tableColumns[cell.column].identifier
                        )
                    else {
                        return nil
                    }

                    return column.value(for: items[cell.row])
                }
            })

            showCopiedRange(range, in: tableView)
            return copiedText
        }

        @MainActor
        func paste(rows: [[String]], in tableView: NSTableView) -> Bool {
            guard
                !rows.isEmpty,
                let startCell = pasteStartCell(in: tableView)
            else {
                return false
            }

            var reloadedRows = IndexSet()
            var didUpdate = false
            let targetRows = pasteTargetRows(rows, from: startCell)

            for target in targetRows {
                guard target.cell.row >= 0, target.cell.row < items.count else { continue }
                guard target.cell.column >= 0, target.cell.column < tableView.numberOfColumns else { continue }
                guard
                    let column = MetadataSpreadsheetColumn(
                        identifier: tableView.tableColumns[target.cell.column].identifier
                    ),
                    column.isEditable,
                    let metadataField = column.metadataField
                else {
                    continue
                }

                let itemID = items[target.cell.row].id
                let newValue = metadataField.editedValue(from: target.value)
                let oldValue = items[target.cell.row].metadataState.current.value(for: metadataField)
                guard oldValue != newValue else { continue }

                items[target.cell.row].metadataState.update(metadataField, to: newValue)
                updateMetadataFieldAction(itemID, metadataField, newValue)
                reloadedRows.insert(target.cell.row)
                didUpdate = true
            }

            guard didUpdate else { return false }

            tableView.reloadData(
                forRowIndexes: reloadedRows,
                columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
            )
            if selectedCellRange == nil {
                selectCell(row: startCell.row, column: startCell.column, extendsSelection: false, in: tableView)
            }
            return true
        }

        @MainActor
        private func firstEditableColumnIndex(in tableView: NSTableView) -> Int {
            tableView.tableColumns.firstIndex { tableColumn in
                MetadataSpreadsheetColumn(identifier: tableColumn.identifier)?.isEditable == true
            } ?? 0
        }

        @MainActor
        private func pasteStartCell(in tableView: NSTableView) -> MetadataCell? {
            guard !items.isEmpty, tableView.numberOfColumns > 0 else { return nil }

            let fallbackRow = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
            let proposedCell = focusedCell ?? MetadataCell(
                row: fallbackRow,
                column: firstEditableColumnIndex(in: tableView)
            )
            let originCell = selectedCellRange?.topLeft ?? proposedCell

            let clampedRow = min(max(originCell.row, 0), items.count - 1)
            let clampedColumn = min(max(originCell.column, 0), tableView.numberOfColumns - 1)

            if let column = MetadataSpreadsheetColumn(identifier: tableView.tableColumns[clampedColumn].identifier),
               column.isEditable {
                return MetadataCell(row: clampedRow, column: clampedColumn)
            }

            return MetadataCell(row: clampedRow, column: firstEditableColumnIndex(in: tableView))
        }

        private func pasteTargetRows(_ rows: [[String]], from startCell: MetadataCell) -> [SpreadsheetPasteTarget] {
            SpreadsheetClipboard.pasteTargets(
                for: rows,
                startCell: startCell,
                selectedRange: selectedCellRange
            )
        }

        @MainActor
        private func showCopiedRange(_ range: MetadataCellRange, in tableView: NSTableView) {
            copyFeedbackWorkItem?.cancel()
            let oldRange = copiedCellRange
            copiedCellRange = range

            var rowIndexes = range.rowIndexes
            if let oldRange {
                rowIndexes.formUnion(oldRange.rowIndexes)
            }
            tableView.reloadData(
                forRowIndexes: rowIndexes,
                columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
            )

            let workItem = DispatchWorkItem { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                let expiredRange = self.copiedCellRange
                self.copiedCellRange = nil
                guard let expiredRange else { return }
                tableView.reloadData(
                    forRowIndexes: expiredRange.rowIndexes,
                    columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
                )
            }
            copyFeedbackWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
        }
    }
}

struct MetadataCell: Equatable {
    var row: Int
    var column: Int
}

struct MetadataCellRange: Equatable {
    var anchor: MetadataCell
    var focused: MetadataCell

    var topLeft: MetadataCell {
        MetadataCell(row: min(anchor.row, focused.row), column: min(anchor.column, focused.column))
    }

    var bottomRight: MetadataCell {
        MetadataCell(row: max(anchor.row, focused.row), column: max(anchor.column, focused.column))
    }

    var rowIndexes: IndexSet {
        IndexSet(integersIn: topLeft.row...bottomRight.row)
    }

    var cells: [MetadataCell] {
        rows.flatMap { $0 }
    }

    var rows: [[MetadataCell]] {
        (topLeft.row...bottomRight.row).map { row in
            (topLeft.column...bottomRight.column).map { column in
                MetadataCell(row: row, column: column)
            }
        }
    }

    func contains(_ cell: MetadataCell) -> Bool {
        topLeft.row...bottomRight.row ~= cell.row
            && topLeft.column...bottomRight.column ~= cell.column
    }
}

struct SpreadsheetPasteTarget: Equatable {
    var cell: MetadataCell
    var value: String
}

private struct MetadataCellVisualState {
    var isFocused: Bool
    var isSelected: Bool
    var isCopied: Bool
}

private final class MetadataCellTextField: NSTextField {
    var itemID: ImportedItem.ID?
    var column: MetadataSpreadsheetColumn?
    var row: Int?

    override func mouseDown(with event: NSEvent) {
        if let tableView = enclosingScrollView?.documentView as? MetadataTableView,
           tableView.handleCellMouseDown(with: event) {
            return
        }

        super.mouseDown(with: event)
    }
}

private final class MetadataCellResetButton: NSButton {
    var itemID: ImportedItem.ID?
    var metadataField: TrackMetadataField?
    var row: Int?
}

private final class MetadataCellView: NSView {
    let textField = MetadataCellTextField(string: String())
    let resetButton = MetadataCellResetButton()
    private var resetButtonWidthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpView()
    }

    func configure(
        itemID: ImportedItem.ID,
        field: TrackMetadataField?,
        row: Int,
        isDirty: Bool,
        visualState: MetadataCellVisualState,
        dirtyBackgroundColor: NSColor
    ) {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = visualState.isFocused || visualState.isCopied ? 2 : 0
        layer?.borderColor = if visualState.isCopied {
            NSColor.systemOrange.cgColor
        } else if visualState.isFocused {
            NSColor.controlAccentColor.cgColor
        } else {
            NSColor.clear.cgColor
        }
        layer?.backgroundColor = backgroundColor(
            isDirty: isDirty,
            visualState: visualState,
            dirtyBackgroundColor: dirtyBackgroundColor
        ).cgColor

        resetButton.itemID = itemID
        resetButton.metadataField = field
        resetButton.row = row
        resetButton.isHidden = !isDirty || field == nil
        resetButton.isEnabled = isDirty && field != nil
        resetButtonWidthConstraint?.constant = isDirty && field != nil ? 18 : 0
        resetButton.toolTip = field.map { "Reset \($0.title) to loaded metadata" }
    }

    private func backgroundColor(
        isDirty: Bool,
        visualState: MetadataCellVisualState,
        dirtyBackgroundColor: NSColor
    ) -> NSColor {
        if visualState.isCopied {
            return NSColor.systemOrange.withAlphaComponent(0.16)
        }

        if visualState.isFocused {
            return NSColor.controlAccentColor.withAlphaComponent(0.16)
        }

        if visualState.isSelected {
            return NSColor.controlAccentColor.withAlphaComponent(0.10)
        }

        return isDirty ? dirtyBackgroundColor : .clear
    }

    private func setUpView() {
        wantsLayer = true

        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.translatesAutoresizingMaskIntoConstraints = false

        resetButton.title = ""
        resetButton.bezelStyle = .inline
        resetButton.isBordered = false
        resetButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Reset Cell"
        )
        resetButton.imagePosition = .imageOnly
        resetButton.contentTintColor = .secondaryLabelColor
        resetButton.setButtonType(.momentaryChange)
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textField)
        addSubview(resetButton)

        let resetButtonWidthConstraint = resetButton.widthAnchor.constraint(equalToConstant: 18)
        self.resetButtonWidthConstraint = resetButtonWidthConstraint

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: resetButton.leadingAnchor, constant: -4),
            resetButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            resetButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            resetButtonWidthConstraint,
            resetButton.heightAnchor.constraint(equalToConstant: 18)
        ])
    }
}

private final class MetadataTableView: NSTableView {
    var focusedCell: MetadataCell?
    var cellSelectionChanged: ((Int, Int, Bool) -> Void)?
    var editFocusedCell: (() -> Void)?
    var copyFocusedCell: (() -> String?)?
    var pasteRows: (([[String]]) -> Bool)?

    @objc func copy(_ sender: Any?) {
        guard let text = copyFocusedCell?() else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard
            let text = NSPasteboard.general.string(forType: .string),
            pasteRows?(SpreadsheetClipboard.rows(from: text)) == true
        else {
            return
        }
    }

    override func keyDown(with event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifierFlags.isDisjoint(with: [.command, .option, .control]) else {
            super.keyDown(with: event)
            return
        }

        let currentRow = focusedCell?.row ?? (selectedRow >= 0 ? selectedRow : 0)
        let currentColumn = focusedCell?.column ?? firstEditableColumnIndex
        let extendsSelection = modifierFlags.contains(.shift)

        switch event.keyCode {
        case 36, 76:
            editFocusedCell?()
        case 123:
            cellSelectionChanged?(currentRow, currentColumn - 1, extendsSelection)
        case 124:
            cellSelectionChanged?(currentRow, currentColumn + 1, extendsSelection)
        case 125:
            cellSelectionChanged?(currentRow + 1, currentColumn, extendsSelection)
        case 126:
            cellSelectionChanged?(currentRow - 1, currentColumn, extendsSelection)
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if handleCellMouseDown(with: event) {
            return
        }

        super.mouseDown(with: event)
    }

    func handleCellMouseDown(with event: NSEvent) -> Bool {
        let location = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: location)
        let clickedColumn = column(at: location)

        guard clickedRow >= 0, clickedColumn >= 0 else {
            return false
        }

        if hitTest(location) is MetadataCellResetButton {
            return false
        }

        let extendsSelection = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.shift)
        cellSelectionChanged?(clickedRow, clickedColumn, extendsSelection)
        window?.makeFirstResponder(self)

        if event.clickCount >= 2 {
            editFocusedCell?()
        }

        return true
    }

    private var firstEditableColumnIndex: Int {
        tableColumns.firstIndex { tableColumn in
            MetadataSpreadsheetColumn(identifier: tableColumn.identifier)?.isEditable == true
        } ?? 0
    }
}

struct SpreadsheetClipboard {
    static func rows(from text: String) -> [[String]] {
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows = normalizedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { row in
                row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            }

        if normalizedText.hasSuffix("\n"), rows.last == [""] {
            rows.removeLast()
        }

        return rows
    }

    static func tsv(from rows: [[String]]) -> String {
        rows.map { row in
            row.joined(separator: "\t")
        }
        .joined(separator: "\n")
    }

    static func pasteTargets(
        for rows: [[String]],
        startCell: MetadataCell,
        selectedRange: MetadataCellRange?
    ) -> [SpreadsheetPasteTarget] {
        guard let firstRow = rows.first else { return [] }
        let isSingleValue = rows.count == 1 && firstRow.count == 1

        if isSingleValue, let selectedRange {
            return selectedRange.cells.map { cell in
                SpreadsheetPasteTarget(cell: cell, value: firstRow[0])
            }
        }

        return rows.enumerated().flatMap { rowOffset, pastedRow in
            pastedRow.enumerated().map { columnOffset, pastedValue in
                SpreadsheetPasteTarget(
                    cell: MetadataCell(
                        row: startCell.row + rowOffset,
                        column: startCell.column + columnOffset
                    ),
                    value: pastedValue
                )
            }
        }
    }
}

private enum MetadataSpreadsheetColumn: String, CaseIterable {
    case file
    case status
    case title
    case artist
    case album
    case albumArtist
    case track
    case disc
    case genre
    case year
    case comment
    case artwork

    init?(identifier: NSUserInterfaceItemIdentifier) {
        self.init(rawValue: identifier.rawValue)
    }

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }

    var cellIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("\(rawValue)-cell")
    }

    var title: String {
        switch self {
        case .file:
            "File"
        case .status:
            "Status"
        case .title:
            TrackMetadataField.title.title
        case .artist:
            TrackMetadataField.artist.title
        case .album:
            TrackMetadataField.album.title
        case .albumArtist:
            TrackMetadataField.albumArtist.title
        case .track:
            TrackMetadataField.track.title
        case .disc:
            TrackMetadataField.disc.title
        case .genre:
            TrackMetadataField.genre.title
        case .year:
            TrackMetadataField.year.title
        case .comment:
            TrackMetadataField.comment.title
        case .artwork:
            TrackMetadataField.artwork.title
        }
    }

    var metadataField: TrackMetadataField? {
        switch self {
        case .file, .status:
            nil
        case .title:
            .title
        case .artist:
            .artist
        case .album:
            .album
        case .albumArtist:
            .albumArtist
        case .track:
            .track
        case .disc:
            .disc
        case .genre:
            .genre
        case .year:
            .year
        case .comment:
            .comment
        case .artwork:
            .artwork
        }
    }

    var isEditable: Bool {
        switch self {
        case .file, .status, .artwork:
            false
        default:
            true
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .file:
            180
        case .status:
            110
        case .track, .disc, .year:
            70
        case .comment:
            180
        case .artwork:
            120
        default:
            120
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .file:
            240
        case .status:
            120
        case .track, .disc, .year:
            80
        case .comment:
            240
        case .artwork:
            150
        default:
            150
        }
    }

    func value(for item: ImportedItem) -> String {
        switch self {
        case .file:
            return item.displayName
        case .status:
            return item.statusTitle
        case .track:
            return item.metadataState.current.track?.number.map(String.init) ?? ""
        case .disc:
            return item.metadataState.current.disc?.number.map(String.init) ?? ""
        case .title, .artist, .album, .albumArtist, .genre, .year, .comment, .artwork:
            guard let metadataField else { return "" }
            return item.metadataState.current.value(for: metadataField).description
        }
    }

    func textColor(for item: ImportedItem) -> NSColor {
        switch self {
        case .status:
            if item.metadataLoadReport.error != nil {
                return .systemRed
            }

            return item.metadataState.hasChanges ? .controlAccentColor : .secondaryLabelColor
        default:
            guard let metadataField else { return .labelColor }
            if item.metadataState.dirtyFields.contains(metadataField) {
                return .controlAccentColor
            }

            return item.metadataLoadReport.missingFields.contains(metadataField)
                ? .tertiaryLabelColor
                : .labelColor
        }
    }

    func isDirty(for item: ImportedItem) -> Bool {
        guard let metadataField else { return false }
        return item.metadataState.dirtyFields.contains(metadataField)
    }

    func backgroundColor(for item: ImportedItem, isFocused: Bool = false) -> NSColor {
        if isFocused {
            return NSColor.controlAccentColor.withAlphaComponent(0.16)
        }

        return isDirty(for: item)
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : .clear
    }
}

private struct ImportSkippedBanner: View {
    let skippedItems: [MP3ImportSkippedItem]
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(skippedItems.count) files skipped")
                    .font(.callout.weight(.semibold))
                Text("Review skipped files before continuing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                ForEach(skippedItems) { item in
                    Text(verbatim: "\(item.displayName): ")
                        + Text(LocalizedStringKey(item.reason.title))
                }
            } label: {
                Label("Details", systemImage: "list.bullet")
            }
            .menuStyle(.button)
            .fixedSize()

            Button(action: dismissAction) {
                Label("Dismiss", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct ImportedItemFooter: View {
    let itemCount: Int

    var body: some View {
        HStack {
            Label("\(itemCount) MP3 files loaded", systemImage: "music.note.list")
                .lineLimit(1)
            Spacer()
            Text("Folders are expanded to supported MP3 files.")
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct InspectorPlaceholder: View {
    let item: ImportedItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Inspector", systemImage: "sidebar.trailing")
                    .font(.headline)

                Divider()

                if let item {
                    InspectorField(label: "File", value: item.displayName)
                    InspectorField(label: "Status", value: item.statusTitle)
                    if let errorMessage = item.metadataLoadReport.error?.message {
                        InspectorField(label: "Read Error", value: errorMessage)
                    }
                    if !item.metadataLoadReport.missingFields.isEmpty {
                        InspectorField(label: "Missing Tags", value: item.missingFieldsSummary)
                    }
                    InspectorField(label: "Title", value: item.metadataState.current.title ?? "")
                    InspectorField(label: "Artist", value: item.metadataState.current.artist ?? "")
                    InspectorField(label: "Album", value: item.metadataState.current.album ?? "")
                    InspectorField(label: "Album Artist", value: item.metadataState.current.albumArtist ?? "")
                    InspectorField(label: "Track", value: item.metadataState.current.track?.description ?? "")
                    InspectorField(label: "Disc", value: item.metadataState.current.disc?.description ?? "")
                    InspectorField(label: "Genre", value: item.metadataState.current.genre ?? "")
                    InspectorField(label: "Year", value: item.metadataState.current.year.map(String.init) ?? "")
                    InspectorField(label: "Comment", value: item.metadataState.current.comment ?? "")
                    InspectorField(label: "Artwork", value: item.metadataState.current.artwork?.description ?? "")
                    InspectorField(label: "URL", value: item.url.absoluteString)
                    InspectorField(label: "Path", value: item.url.path)
                } else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "doc",
                        description: Text("Select a loaded URL to inspect its details.")
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)
    }
}

private struct InspectorField: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ImportedItem: Identifiable, Hashable {
    let url: URL
    var metadataLoadReport: TrackMetadataLoadReport
    var metadataState: EditableTrackMetadata

    var id: URL { url }

    static func == (lhs: ImportedItem, rhs: ImportedItem) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    init(url: URL, metadataLoadReport: TrackMetadataLoadReport = TrackMetadataLoadReport(metadata: TrackMetadata())) {
        self.url = url
        self.metadataLoadReport = metadataLoadReport
        self.metadataState = EditableTrackMetadata(original: metadataLoadReport.metadata)
    }

    var statusTitle: String {
        if metadataLoadReport.error != nil {
            return "Read Error"
        }

        return metadataState.hasChanges ? "Modified" : "Loaded"
    }

    var statusSystemImage: String {
        if metadataLoadReport.error != nil {
            return "exclamationmark.triangle"
        }

        return metadataState.hasChanges ? "pencil.circle" : "checkmark.circle"
    }

    var statusStyle: AnyShapeStyle {
        if metadataLoadReport.error != nil {
            return AnyShapeStyle(.red)
        }

        return AnyShapeStyle(.secondary)
    }

    var missingFieldsSummary: String {
        metadataLoadReport.missingFields
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
            .joined(separator: ", ")
    }

    var displayName: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    var systemImage: String {
        "music.note"
    }
}

private enum SidebarItem: String, CaseIterable, Identifiable {
    case library
    case folders
    case pendingChanges

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .library:
            "Library"
        case .folders:
            "Folders"
        case .pendingChanges:
            "Pending Changes"
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            "music.note.list"
        case .folders:
            "folder"
        case .pendingChanges:
            "square.and.pencil"
        }
    }
}

#Preview {
    ContentView()
}

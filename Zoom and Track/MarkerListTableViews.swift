import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MarkerListTableView: NSViewRepresentable {
    let entries: [MarkerListEntry]
    let selectedMarkerID: String?
    let onSelectMarker: (String) -> Void
    let onToggleMarkerEnabled: (String) -> Void
    let onReorderMarkers: ([String]) -> Void
    @Binding var renamingMarkerID: String?
    @Binding var markerNameDraft: String
    let onBeginRename: (ZoomPlanItem) -> Void
    let onCommitRename: (String, String) -> Void
    let onCancelRename: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = MarkerListNativeTableView()
        tableView.headerView = nil
        tableView.rowHeight = 76
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.style = .plain
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.registerForDraggedTypes([.string])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.handleTableViewAction(_:))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MarkerColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refreshTableIfNeeded()
        context.coordinator.syncSelection()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: MarkerListTableView
        weak var tableView: NSTableView?
        private var isProgrammaticSelectionChange = false
        private var draggedMarkerID: String?
        private var lastRenderedEntryIDs: [String] = []
        private var lastRenderedSelectionID: String?
        private var lastRenderedHighlightSignature: String = ""
        private var lastRenderedRenamingMarkerID: String?

        init(parent: MarkerListTableView) {
            self.parent = parent
        }

        @objc
        func handleTableViewAction(_ sender: Any?) {
            guard let tableView else { return }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0, row < parent.entries.count else { return }
            if let renamingMarkerID = parent.renamingMarkerID {
                parent.onCommitRename(renamingMarkerID, parent.markerNameDraft)
            }
            parent.onSelectMarker(parent.entries[row].id)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.entries.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            76
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("MarkerListHostingCellView")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? MarkerListHostingCellView) ?? MarkerListHostingCellView(identifier: identifier)
            let entry = parent.entries[row]
            cell.update(
                rootView: MarkerListCellContent(
                    entry: entry,
                    onToggleEnabled: { [weak self] in
                        self?.parent.onToggleMarkerEnabled(entry.id)
                    },
                    renamingMarkerID: parent.$renamingMarkerID,
                    markerNameDraft: parent.$markerNameDraft,
                    onBeginRename: { [weak self] in
                        self?.parent.onBeginRename(entry.marker)
                    },
                    onCommitRename: { [weak self] name in
                        self?.parent.onCommitRename(entry.id, name)
                    },
                    onCancelRename: { [weak self] in
                        self?.parent.onCancelRename()
                    }
                )
            )
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isProgrammaticSelectionChange,
                  let tableView,
                  tableView.selectedRow >= 0,
                  tableView.selectedRow < parent.entries.count else {
                return
            }

            if let renamingMarkerID = parent.renamingMarkerID {
                parent.onCommitRename(renamingMarkerID, parent.markerNameDraft)
            }
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row < parent.entries.count else { return nil }
            let markerID = parent.entries[row].id
            draggedMarkerID = markerID
            let item = NSPasteboardItem()
            item.setString(markerID, forType: .string)
            return item
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            let markerIDs = parent.entries.map(\.id)
            guard let draggedMarkerID = draggedMarkerID ?? info.draggingPasteboard.string(forType: .string),
                  let fromIndex = markerIDs.firstIndex(of: draggedMarkerID) else {
                return false
            }

            var reordered = markerIDs
            let draggedID = reordered.remove(at: fromIndex)
            let insertionIndex = max(0, min(row > fromIndex ? row - 1 : row, reordered.count))
            reordered.insert(draggedID, at: insertionIndex)
            parent.onReorderMarkers(reordered)
            self.draggedMarkerID = nil
            return true
        }

        func syncSelection() {
            guard let tableView else { return }
            let targetRow = parent.entries.firstIndex { $0.id == parent.selectedMarkerID } ?? -1
            if tableView.selectedRow != targetRow {
                isProgrammaticSelectionChange = true
                if targetRow >= 0 {
                    tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
                    tableView.scrollRowToVisible(targetRow)
                } else {
                    tableView.deselectAll(nil)
                }
                isProgrammaticSelectionChange = false
            } else if targetRow >= 0 {
                tableView.scrollRowToVisible(targetRow)
            }
        }

        func refreshTableIfNeeded() {
            guard let tableView else { return }

            let entryIDs = parent.entries.map(\.id)
            let selectionID = parent.selectedMarkerID
            let highlightSignature = parent.entries.map { "\($0.id):\($0.isSelected):\($0.isPlaybackHighlighted):\($0.marker.markerName ?? ""):\($0.marker.enabled)" }.joined(separator: "|")
            let renamingMarkerID = parent.renamingMarkerID

            let shouldReload: Bool
            if let renamingMarkerID, renamingMarkerID == lastRenderedRenamingMarkerID {
                shouldReload = false
            } else {
                shouldReload =
                    entryIDs != lastRenderedEntryIDs ||
                    selectionID != lastRenderedSelectionID ||
                    highlightSignature != lastRenderedHighlightSignature ||
                    renamingMarkerID != lastRenderedRenamingMarkerID
            }

            if shouldReload {
                tableView.reloadData()
                lastRenderedEntryIDs = entryIDs
                lastRenderedSelectionID = selectionID
                lastRenderedHighlightSignature = highlightSignature
                lastRenderedRenamingMarkerID = renamingMarkerID
            }
        }
    }
}

private struct MarkerListCellContent: View {
    let entry: MarkerListEntry
    let onToggleEnabled: () -> Void
    @Binding var renamingMarkerID: String?
    @Binding var markerNameDraft: String
    let onBeginRename: () -> Void
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void
    @FocusState private var isNameFieldFocused: Bool
    @State private var isRenameButtonHovered = false

    var body: some View {
        let marker = entry.marker
        let resolvedMarkerName = (marker.markerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (marker.markerName ?? "")
            : "Unnamed Marker"
        let isRenaming = renamingMarkerID == entry.id
        let backgroundFill: Color = entry.isPlaybackHighlighted
            ? Color.accentColor.opacity(0.20)
            : entry.isSelected
            ? Color.accentColor.opacity(0.12)
            : Color.clear
        let strokeColor: Color = entry.isPlaybackHighlighted
            ? Color.accentColor.opacity(0.55)
            : entry.isSelected
            ? Color.accentColor.opacity(0.35)
            : Color.secondary.opacity(0.08)

        HStack(alignment: .top, spacing: 10) {
            dragGrip

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(timecodeString(marker.sourceEventTimestamp))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 88, alignment: .leading)
                    Spacer(minLength: 0)
                    Button(action: onToggleEnabled) {
                        HStack(spacing: 4) {
                            Image(systemName: marker.enabled ? "checkmark.circle.fill" : "circle")
                            Text(marker.enabled ? "On" : "Off")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(marker.enabled ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    if isRenaming {
                        TextField("", text: $markerNameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
                            )
                            .focused($isNameFieldFocused)
                            .onSubmit {
                                onCommitRename(markerNameDraft)
                            }
                            .onAppear {
                                DispatchQueue.main.async {
                                    isNameFieldFocused = true
                                }
                            }
                    } else {
                        Text(resolvedMarkerName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }

                    Button {
                        if !isRenaming {
                            onBeginRename()
                        }
                    } label: {
                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isRenameButtonHovered ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        isRenameButtonHovered = isHovered
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    Label {
                        Text(String(format: "%.1fx", marker.zoomScale))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    } icon: {
                        Image(systemName: "viewfinder.rectangular")
                    }

                    Label {
                        Text(String(format: "%.2fs", marker.totalSegmentDuration))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    } icon: {
                        Image(systemName: "timer")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if entry.isPlaybackHighlighted {
                Capsule(style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 4)
                    .padding(.vertical, 8)
                    .padding(.leading, 2)
            }
        }
        .opacity(marker.enabled ? 1.0 : 0.5)
        .contentShape(Rectangle())
        .onChange(of: isNameFieldFocused) { _, isFocused in
            guard isRenaming, !isFocused else { return }
            onCommitRename(markerNameDraft)
        }
    }

    private var dragGrip: some View {
        HStack(spacing: 3) {
            VStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(0.65))
                        .frame(width: 2.5, height: 2.5)
                }
            }
            VStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(0.65))
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
        .frame(width: 16)
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }

    private func timecodeString(_ seconds: Double) -> String {
        let clampedSeconds = max(seconds, 0)
        let totalFrames = Int(clampedSeconds * 30)
        let hours = totalFrames / (30 * 60 * 60)
        let minutes = (totalFrames / (30 * 60)) % 60
        let secs = (totalFrames / 30) % 60
        let frames = totalFrames % 30
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
    }
}

private final class MarkerListHostingCellView: NSTableCellView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setFrameSize(.zero)
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rootView: MarkerListCellContent) {
        hostingView.rootView = AnyView(rootView)
    }
}

private final class MarkerListNativeTableView: NSTableView {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
}

private struct MarkerListReorderDropDelegate: DropDelegate {
    let targetMarkerID: String
    @Binding var previewOrder: [String]?
    @Binding var draggedMarkerID: String?
    @Binding var dropTargetMarkerID: String?
    let reorderAction: ([String]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        guard let draggedMarkerID, draggedMarkerID != targetMarkerID else { return }
        dropTargetMarkerID = targetMarkerID
        guard var previewOrder,
              let fromIndex = previewOrder.firstIndex(of: draggedMarkerID),
              let toIndex = previewOrder.firstIndex(of: targetMarkerID),
              fromIndex != toIndex else { return }

        let draggedID = previewOrder.remove(at: fromIndex)
        previewOrder.insert(draggedID, at: toIndex)
        self.previewOrder = previewOrder
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if draggedMarkerID != targetMarkerID {
            dropTargetMarkerID = targetMarkerID
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedMarkerID, draggedMarkerID != targetMarkerID else {
            self.draggedMarkerID = nil
            dropTargetMarkerID = nil
            previewOrder = nil
            return false
        }

        guard let previewOrder else {
            self.draggedMarkerID = nil
            dropTargetMarkerID = nil
            return false
        }

        reorderAction(previewOrder)
        self.draggedMarkerID = nil
        dropTargetMarkerID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.previewOrder = nil
        }
        return true
    }

    func dropExited(info: DropInfo) {
        if !info.hasItemsConforming(to: [UTType.text]), dropTargetMarkerID == targetMarkerID {
            dropTargetMarkerID = nil
        }
    }
}

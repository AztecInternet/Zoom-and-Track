import AppKit
import SwiftUI

struct EffectTimelineSegmentLayout: Identifiable {
    let marker: EffectPlanItem
    let lane: Int
    let startRatio: Double
    let eventRatio: Double
    let endRatio: Double

    var id: String { marker.id }
}

struct EffectTimelineSegmentView: View {
    let layout: EffectTimelineSegmentLayout
    let width: CGFloat
    let verticalOrigin: CGFloat
    let isSelected: Bool
    let isEnabled: Bool
    let isPlaybackHighlighted: Bool
    let onSelect: () -> Void

    var body: some View {
        let laneHeight: CGFloat = 9
        let laneSpacing: CGFloat = 4
        let laneY = verticalOrigin + (CGFloat(layout.lane) * (laneHeight + laneSpacing))
        let startX = CGFloat(layout.startRatio) * width
        let endX = CGFloat(layout.endRatio) * width
        let eventX = CGFloat(layout.eventRatio) * width
        let barWidth = max(endX - startX, 12)
        let baseColor: Color = isSelected
            ? .accentColor
            : (isEnabled ? Color.orange.opacity(0.82) : Color.secondary.opacity(0.35))
        let barColor = isPlaybackHighlighted ? Color.accentColor : baseColor

        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(barColor.opacity(isSelected ? 0.88 : 0.62))
                .frame(width: barWidth, height: laneHeight)
                .position(x: startX + (barWidth / 2), y: laneY)

            Capsule(style: .continuous)
                .fill(barColor.opacity(isSelected ? 1 : 0.82))
                .frame(width: isSelected ? 8 : 6, height: isSelected ? 18 : 14)
                .position(x: eventX, y: laneY)

            if isSelected {
                Capsule(style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 4)
                    .frame(width: 12, height: 22)
                    .position(x: eventX, y: laneY)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

struct EffectListEntry: Identifiable {
    let marker: EffectPlanItem
    let markerNumber: Int
    let isSelected: Bool
    let isPlaybackHighlighted: Bool

    var id: String { marker.id }
}

struct EffectListTableView: NSViewRepresentable {
    let entries: [EffectListEntry]
    let selectedMarkerID: String?
    let onSelectMarker: (String) -> Void
    let onToggleMarkerEnabled: (String) -> Void
    let onReorderMarkers: ([String]) -> Void
    @Binding var renamingMarkerID: String?
    @Binding var markerNameDraft: String
    let onBeginRename: (EffectPlanItem) -> Void
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

        let tableView = EffectListNativeTableView()
        tableView.headerView = nil
        tableView.rowHeight = 78
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

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("EffectColumn"))
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
        var parent: EffectListTableView
        weak var tableView: NSTableView?
        private var isProgrammaticSelectionChange = false
        private var draggedMarkerID: String?
        private var lastRenderedEntryIDs: [String] = []
        private var lastRenderedSelectionID: String?
        private var lastRenderedHighlightSignature: String = ""
        private var lastRenderedRenamingMarkerID: String?

        init(parent: EffectListTableView) {
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
            78
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("EffectListHostingCellView")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? EffectListHostingCellView) ?? EffectListHostingCellView(identifier: identifier)
            let entry = parent.entries[row]
            cell.update(
                rootView: EffectListCellContent(
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
            let highlightSignature = parent.entries.map {
                "\($0.id):\($0.isSelected):\($0.isPlaybackHighlighted):\($0.marker.markerName ?? ""):\($0.marker.enabled):\($0.marker.style.rawValue):\($0.marker.amount):\($0.marker.blurAmount):\($0.marker.darkenAmount):\($0.marker.tintAmount):\($0.marker.fadeInDuration):\($0.marker.fadeOutDuration):\($0.marker.cornerRadius):\($0.marker.feather)"
            }.joined(separator: "|")
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

private struct EffectListCellContent: View {
    let entry: EffectListEntry
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
            : "Unnamed Effect"
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
                    Text(marker.style.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
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
                        Text(effectAmountSummary(for: marker))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    } icon: {
                        Image(systemName: "dial.medium")
                    }

                    Label {
                        Text(String(format: "%.2fs / %.2fs", marker.fadeInDuration, marker.fadeOutDuration))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    } icon: {
                        Image(systemName: "timer")
                    }

                    Label {
                        Text(String(format: "%.2fs", max(marker.endTime - marker.sourceEventTimestamp, 0.05)))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    } icon: {
                        Image(systemName: "pause.rectangle")
                    }

                    Label {
                        Text(String(format: "%.0f", marker.cornerRadius))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    } icon: {
                        Image(systemName: "roundedcorners")
                    }

                    Label {
                        Text(String(format: "%.0f", marker.feather))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    } icon: {
                        Image(systemName: "drop.degreesign")
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

    private func effectAmountSummary(for marker: EffectPlanItem) -> String {
        switch marker.style {
        case .blur:
            return String(format: "B %.0f%%", marker.blurAmount * 100)
        case .darken:
            return String(format: "D %.0f%%", marker.darkenAmount * 100)
        case .tint:
            return String(format: "T %.0f%%", marker.tintAmount * 100)
        case .blurDarken:
            return String(format: "B %.0f%% D %.0f%%", marker.blurAmount * 100, marker.darkenAmount * 100)
        }
    }
}

private final class EffectListHostingCellView: NSTableCellView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.translatesAutoresizingMaskIntoConstraints = false
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
        nil
    }

    func update(rootView: EffectListCellContent) {
        hostingView.rootView = AnyView(rootView)
    }
}

private final class EffectListNativeTableView: NSTableView {
    override func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }
}

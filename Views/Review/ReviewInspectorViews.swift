import AppKit
import SwiftUI

enum EditInspectorMode: String, CaseIterable, Identifiable {
    case suggestions = "Suggestions"
    case captureInfo = "Capture Info"
    case markers = "Markers"

    var id: String { rawValue }
}

struct InspectorSectionHeaderView: View {
    let title: String
    let accentRole: FlowTrackAccentRole?

    init(title: String, accentRole: FlowTrackAccentRole? = nil) {
        self.title = title
        self.accentRole = accentRole
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

struct EffectsInspectorPlaceholderView: View {
    let effectMarkerCount: Int
    let accentRole: FlowTrackAccentRole?

    init(effectMarkerCount: Int, accentRole: FlowTrackAccentRole? = nil) {
        self.effectMarkerCount = effectMarkerCount
        self.accentRole = accentRole
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                InspectorSectionHeaderView(title: "Effects", accentRole: accentRole)
                Text("Create effect markers from the timeline, then select one to tune its style, timing, and focus region.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                InspectorSectionHeaderView(title: "Status", accentRole: accentRole)
                Text(effectMarkerCount == 0 ? "No effect markers yet" : "\(effectMarkerCount) effect marker" + (effectMarkerCount == 1 ? "" : "s"))
                    .font(.system(size: 13, weight: .medium))
                Text("Zoom & Click bars remain visible in the timeline as non-editable grey reference guides while you are in Effects mode.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct NativeOverflowScrollPane<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NativeInspectorScrollHost(content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
    }
}

struct InspectorOverflowHintView: View {
    var body: some View {
        Text("scroll for more")
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(Color.accentColor.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
            )
            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
    }
}

private struct InspectorScrollMetrics: Equatable {
    var contentHeight: CGFloat
    var contentOffset: CGFloat
    var viewportHeight: CGFloat
}

private struct InspectorPaneContainer<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
    }
}

private struct InspectorBottomContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ResizableInspectorSplitView<TopContent: View, BottomContent: View>: View {
    @State private var topSectionFraction: CGFloat = 0.42
    @State private var bottomContentHeight: CGFloat = 0

    let minTopHeight: CGFloat
    let minBottomHeight: CGFloat
    @ViewBuilder let topContent: TopContent
    @ViewBuilder let bottomContent: BottomContent

    init(
        minTopHeight: CGFloat = 180,
        minBottomHeight: CGFloat = 220,
        @ViewBuilder topContent: () -> TopContent,
        @ViewBuilder bottomContent: () -> BottomContent
    ) {
        self.minTopHeight = minTopHeight
        self.minBottomHeight = minBottomHeight
        self.topContent = topContent()
        self.bottomContent = bottomContent()
    }

    var body: some View {
        NativeInspectorSplitView(
            topSectionFraction: $topSectionFraction,
            minTopHeight: minTopHeight,
            minBottomHeight: minBottomHeight,
            maxBottomHeight: measuredBottomMaximumHeight,
            topContent: {
                InspectorPaneContainer {
                    topContent
                        .padding(.bottom, 0)
                }
            },
            bottomContent: {
                NativeOverflowScrollPane {
                    bottomContent
                        .padding(.top, 12)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: InspectorBottomContentHeightKey.self, value: proxy.size.height)
                            }
                        )
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPreferenceChange(InspectorBottomContentHeightKey.self) { height in
            guard height > 0, abs(height - bottomContentHeight) > 0.5 else { return }
            bottomContentHeight = height
        }
    }

    private var measuredBottomMaximumHeight: CGFloat? {
        guard bottomContentHeight > 0 else { return nil }
        return max(minBottomHeight, bottomContentHeight + 10)
    }
}

private struct NativeInspectorScrollHost<Content: View>: NSViewRepresentable {
    let content: Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView(rootView: AnyView(content))
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(scrollView: nsView, rootView: AnyView(content))
    }

    final class Coordinator: NSObject {
        private let documentView = InspectorScrollDocumentView()
        private var boundsObserver: NSObjectProtocol?

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func makeScrollView(rootView: AnyView) -> NSScrollView {
            let scrollView = InspectorOverflowHintingScrollView()
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.borderType = .noBorder
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollView.documentView = documentView
            scrollView.observeDocumentView(documentView)

            documentView.update(rootView: rootView)
            installBoundsObserver(for: scrollView)
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.updateLayout(for: scrollView)
                scrollView.updateOverflowHintVisibility(animated: false)
            }
            return scrollView
        }

        func update(scrollView: NSScrollView, rootView: AnyView) {
            documentView.update(rootView: rootView)
            updateLayout(for: scrollView)
            DispatchQueue.main.async { [weak scrollView] in
                (scrollView as? InspectorOverflowHintingScrollView)?.updateOverflowHintVisibility(animated: false)
            }
        }

        private func installBoundsObserver(for scrollView: NSScrollView) {
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.publishMetrics(for: scrollView)
            }
        }

        private func updateLayout(for scrollView: NSScrollView) {
            let viewportHeight = scrollView.contentView.bounds.height
            let viewportWidth = scrollView.contentView.bounds.width
            guard viewportWidth > 0 else { return }

            documentView.updateWidth(viewportWidth)
            documentView.layoutSubtreeIfNeeded()
            let contentHeight = documentView.contentFittingHeight
            documentView.setFrameSize(NSSize(width: viewportWidth, height: max(contentHeight, viewportHeight)))
            documentView.needsLayout = true
            documentView.layoutSubtreeIfNeeded()
            publishMetrics(for: scrollView)
        }

        private func publishMetrics(for scrollView: NSScrollView) {
            (scrollView as? InspectorOverflowHintingScrollView)?.updateOverflowHintVisibility()
        }
    }
}

private final class InspectorScrollDocumentView: NSView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentWidth: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var contentFittingHeight: CGFloat {
        if currentWidth > 0 {
            hostingView.setFrameSize(NSSize(width: currentWidth, height: 1))
        }
        return hostingView.fittingSize.height
    }

    func update(rootView: AnyView) {
        hostingView.rootView = rootView
    }

    func updateWidth(_ width: CGFloat) {
        currentWidth = width
    }

    override func layout() {
        super.layout()
        hostingView.frame = CGRect(origin: .zero, size: CGSize(width: bounds.width, height: bounds.height))
    }
}

final class InspectorOverflowHintingScrollView: NSScrollView {
    private let hintHostingView = InspectorOverflowHintHostingView(rootView: AnyView(InspectorOverflowHintView()))
    private var boundsObserver: NSObjectProtocol?
    private var documentFrameObserver: NSObjectProtocol?
    private weak var observedDocumentView: NSView?
    private var isHintVisible = false
    private var hadHiddenContentBelow = false
    private var hideWorkItem: DispatchWorkItem?
    private var suppressTriggersUntil = Date.distantPast
    private var lastObservedContentOffset: CGFloat = 0

    private let hintVisibleDuration: TimeInterval = 2.0
    private let hintFadeDuration: TimeInterval = 0.5
    private let retriggerSuppressionDuration: TimeInterval = 30.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupOverflowHint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        if let documentFrameObserver {
            NotificationCenter.default.removeObserver(documentFrameObserver)
        }
        observedDocumentView?.postsFrameChangedNotifications = false
    }

    private func setupOverflowHint() {
        contentView.postsBoundsChangedNotifications = true
        hintHostingView.translatesAutoresizingMaskIntoConstraints = true
        hintHostingView.frame = .zero
        addSubview(hintHostingView, positioned: .above, relativeTo: nil)
        hintHostingView.alphaValue = 0
        hintHostingView.isHidden = true

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            self?.handleBoundsChanged()
        }
    }

    func observeDocumentView(_ documentView: NSView?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self, weak documentView] in
                self?.observeDocumentView(documentView)
            }
            return
        }

        if let documentFrameObserver {
            NotificationCenter.default.removeObserver(documentFrameObserver)
            self.documentFrameObserver = nil
        }
        observedDocumentView?.postsFrameChangedNotifications = false
        observedDocumentView = documentView

        guard let documentView else { return }
        documentView.postsFrameChangedNotifications = true
        documentFrameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: documentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateOverflowHintVisibility(animated: false)
        }
        updateOverflowHintVisibility(animated: false)
    }

    override func layout() {
        super.layout()
        layoutHintView()
        updateOverflowHintVisibility(animated: false)
    }

    private func layoutHintView() {
        let fittingSize = hintHostingView.fittingSize
        let x = floor((bounds.width - fittingSize.width) / 2)
        let y = 6.0
        hintHostingView.frame = CGRect(
            x: x,
            y: y,
            width: fittingSize.width,
            height: fittingSize.height
        )
        addSubview(hintHostingView, positioned: .above, relativeTo: nil)
    }

    func updateOverflowHintVisibility(animated: Bool = true) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateOverflowHintVisibility(animated: animated)
            }
            return
        }

        guard let documentView = observedDocumentView else {
            hadHiddenContentBelow = false
            hideHint(animated: animated)
            return
        }

        let remainingContentBelow = documentView.frame.height - contentView.documentVisibleRect.maxY
        let hasHiddenContentBelow = remainingContentBelow > 2

        if !hasHiddenContentBelow {
            hadHiddenContentBelow = false
            hideHint(animated: animated)
            return
        }

        if !hadHiddenContentBelow {
            hadHiddenContentBelow = true
            triggerHintIfAllowed(animated: animated)
        }
    }

    private func handleBoundsChanged() {
        let newOffset = contentView.bounds.origin.y
        let didScroll = abs(newOffset - lastObservedContentOffset) > 0.5
        lastObservedContentOffset = newOffset

        if didScroll {
            suppressTriggersUntil = Date().addingTimeInterval(retriggerSuppressionDuration)
        }

        updateOverflowHintVisibility(animated: false)
    }

    private func triggerHintIfAllowed(animated: Bool) {
        guard Date() >= suppressTriggersUntil else { return }
        showHint(animated: true)
    }

    private func showHint(animated: Bool) {
        hideWorkItem?.cancel()
        isHintVisible = true
        hintHostingView.isHidden = false

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                hintHostingView.animator().alphaValue = 1
            }
        } else {
            hintHostingView.alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideHint(animated: true)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hintVisibleDuration, execute: workItem)
    }

    private func hideHint(animated: Bool) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard isHintVisible || !hintHostingView.isHidden else { return }
        isHintVisible = false

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = hintFadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                hintHostingView.animator().alphaValue = 0
            } completionHandler: { [weak hintHostingView] in
                hintHostingView?.isHidden = true
            }
        } else {
            hintHostingView.alphaValue = 0
            hintHostingView.isHidden = true
        }
    }
}

private final class InspectorOverflowHintHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct NativeInspectorSplitView<TopPane: View, BottomPane: View>: NSViewRepresentable {
    @Binding var topSectionFraction: CGFloat
    let minTopHeight: CGFloat
    let minBottomHeight: CGFloat
    let maxBottomHeight: CGFloat?
    let topContent: TopPane
    let bottomContent: BottomPane

    init(
        topSectionFraction: Binding<CGFloat>,
        minTopHeight: CGFloat,
        minBottomHeight: CGFloat,
        maxBottomHeight: CGFloat?,
        @ViewBuilder topContent: () -> TopPane,
        @ViewBuilder bottomContent: () -> BottomPane
    ) {
        self._topSectionFraction = topSectionFraction
        self.minTopHeight = minTopHeight
        self.minBottomHeight = minBottomHeight
        self.maxBottomHeight = maxBottomHeight
        self.topContent = topContent()
        self.bottomContent = bottomContent()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(topSectionFraction: $topSectionFraction)
    }

    func makeNSView(context: Context) -> InspectorSplitView {
        context.coordinator.makeSplitView(
            minTopHeight: minTopHeight,
            minBottomHeight: minBottomHeight,
            maxBottomHeight: maxBottomHeight,
            topContent: AnyView(topContent),
            bottomContent: AnyView(bottomContent)
        )
    }

    func updateNSView(_ nsView: InspectorSplitView, context: Context) {
        context.coordinator.update(
            splitView: nsView,
            minTopHeight: minTopHeight,
            minBottomHeight: minBottomHeight,
            maxBottomHeight: maxBottomHeight,
            topContent: AnyView(topContent),
            bottomContent: AnyView(bottomContent),
            desiredFraction: topSectionFraction
        )
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        @Binding private var topSectionFraction: CGFloat
        private let topHostingView = NSHostingView(rootView: AnyView(EmptyView()))
        private let bottomHostingView = NSHostingView(rootView: AnyView(EmptyView()))
        private var isApplyingProgrammaticLayout = false
        private var pendingTopSectionFraction: CGFloat?
        private var minTopHeight: CGFloat = 180
        private var minBottomHeight: CGFloat = 220
        private var maxBottomHeight: CGFloat?

        init(topSectionFraction: Binding<CGFloat>) {
            self._topSectionFraction = topSectionFraction
        }

        func makeSplitView(
            minTopHeight: CGFloat,
            minBottomHeight: CGFloat,
            maxBottomHeight: CGFloat?,
            topContent: AnyView,
            bottomContent: AnyView
        ) -> InspectorSplitView {
            self.minTopHeight = minTopHeight
            self.minBottomHeight = minBottomHeight
            self.maxBottomHeight = maxBottomHeight

            let splitView = InspectorSplitView()
            splitView.delegate = self
            splitView.isVertical = false
            splitView.dividerStyle = .thin
            splitView.autosaveName = nil

            let topContainer = InspectorSplitPaneView()
            let bottomContainer = InspectorSplitPaneView()

            install(hostingView: topHostingView, in: topContainer, rootView: topContent)
            install(hostingView: bottomHostingView, in: bottomContainer, rootView: bottomContent)

            splitView.addArrangedSubview(topContainer)
            splitView.addArrangedSubview(bottomContainer)

            DispatchQueue.main.async { [weak self, weak splitView] in
                guard let self, let splitView else { return }
                self.applyLayout(to: splitView, desiredFraction: self.topSectionFraction)
            }

            return splitView
        }

        func update(
            splitView: InspectorSplitView,
            minTopHeight: CGFloat,
            minBottomHeight: CGFloat,
            maxBottomHeight: CGFloat?,
            topContent: AnyView,
            bottomContent: AnyView,
            desiredFraction: CGFloat
        ) {
            self.minTopHeight = minTopHeight
            self.minBottomHeight = minBottomHeight
            self.maxBottomHeight = maxBottomHeight
            topHostingView.rootView = topContent
            bottomHostingView.rootView = bottomContent
            applyLayout(to: splitView, desiredFraction: desiredFraction)
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !isApplyingProgrammaticLayout,
                  let splitView = notification.object as? NSSplitView,
                  splitView.subviews.count >= 2 else {
                return
            }

            let availableHeight = max(splitView.bounds.height - splitView.dividerThickness, 1)
            let currentTopHeight = splitView.subviews[0].frame.height
            let newFraction = min(max(currentTopHeight / availableHeight, 0), 1)

            guard abs(newFraction - topSectionFraction) > 0.0001 else { return }
            pendingTopSectionFraction = newFraction

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let pendingFraction = self.pendingTopSectionFraction else {
                    return
                }

                self.pendingTopSectionFraction = nil
                guard abs(pendingFraction - self.topSectionFraction) > 0.0001 else { return }
                self.topSectionFraction = pendingFraction
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            let availableHeight = max(splitView.bounds.height - splitView.dividerThickness, 1)
            return max(minTopHeight, availableHeight - resolvedMaxBottomHeight(for: availableHeight))
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            splitView.bounds.height - splitView.dividerThickness - minBottomHeight
        }

        private func applyLayout(to splitView: NSSplitView, desiredFraction: CGFloat) {
            guard splitView.subviews.count >= 2 else { return }
            let availableHeight = splitView.bounds.height - splitView.dividerThickness
            guard availableHeight > 0 else { return }

            let minTopCoordinate = max(minTopHeight, availableHeight - resolvedMaxBottomHeight(for: availableHeight))
            let minFraction = min(max(minTopCoordinate / availableHeight, 0.15), 0.95)
            let maxFraction = max(min(1 - (minBottomHeight / availableHeight), 0.85), minFraction)
            let clampedFraction = min(max(desiredFraction, minFraction), maxFraction)
            let topHeight = availableHeight * clampedFraction

            let currentTopHeight = splitView.subviews[0].frame.height
            guard abs(currentTopHeight - topHeight) > 0.5 else { return }

            isApplyingProgrammaticLayout = true
            splitView.setPosition(topHeight, ofDividerAt: 0)
            splitView.adjustSubviews()
            isApplyingProgrammaticLayout = false
        }

        private func install(hostingView: NSHostingView<AnyView>, in container: NSView, rootView: AnyView) {
            hostingView.rootView = rootView
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: container.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        private func resolvedMaxBottomHeight(for availableHeight: CGFloat) -> CGFloat {
            guard let maxBottomHeight else {
                return availableHeight
            }

            return min(max(maxBottomHeight, minBottomHeight), availableHeight)
        }
    }
}

private final class InspectorSplitView: NSSplitView {
    override var isFlipped: Bool { true }
    override var dividerThickness: CGFloat { 8 }

    override func drawDivider(in rect: NSRect) {
        let separatorRect = NSRect(
            x: rect.minX,
            y: rect.midY - 0.5,
            width: rect.width,
            height: 1
        )
        NSColor.separatorColor.withAlphaComponent(0.65).setFill()
        NSBezierPath(rect: separatorRect).fill()

        let handleWidth: CGFloat = min(42, max(28, rect.width * 0.18))
        let handleHeight: CGFloat = 4
        let handleRect = NSRect(
            x: rect.midX - handleWidth / 2,
            y: rect.midY - handleHeight / 2,
            width: handleWidth,
            height: handleHeight
        )
        NSColor.tertiaryLabelColor.withAlphaComponent(0.75).setFill()
        NSBezierPath(
            roundedRect: handleRect,
            xRadius: handleHeight / 2,
            yRadius: handleHeight / 2
        ).fill()
    }
}

private final class InspectorSplitPaneView: NSView {
    override var isFlipped: Bool { true }
}

struct ReviewInspectorCard<PrimaryContent: View, EffectsContent: View>: View {
    let editorMode: ReviewEditorMode
    @Binding var inspectorMode: EditInspectorMode
    let effectMarkerCount: Int
    let accentRole: FlowTrackAccentRole?
    @ViewBuilder let primaryContent: PrimaryContent
    @ViewBuilder let effectsContent: EffectsContent

    init(
        editorMode: ReviewEditorMode,
        inspectorMode: Binding<EditInspectorMode>,
        effectMarkerCount: Int,
        accentRole: FlowTrackAccentRole? = nil,
        @ViewBuilder primaryContent: () -> PrimaryContent,
        @ViewBuilder effectsContent: () -> EffectsContent
    ) {
        self.editorMode = editorMode
        self._inspectorMode = inspectorMode
        self.effectMarkerCount = effectMarkerCount
        self.accentRole = accentRole
        self.primaryContent = primaryContent()
        self.effectsContent = effectsContent()
    }

    var body: some View {
        let resolvedAccentRole: FlowTrackAccentRole? = inspectorMode == .captureInfo
            ? nil
            : (accentRole ?? (editorMode == .effects ? .effects : .zoomAndClicks))
        let headerText: (title: String, subtitle: String?) = {
            switch inspectorMode {
            case .suggestions:
                return ("Suggestions", "Review local editing opportunities")
            case .captureInfo:
                return ("Capture Info", nil)
            case .markers:
                if editorMode == .effects {
                    return ("Effects Inspector", "Editing effect timing, style, and focus region")
                } else {
                    return ("Zoom & Clicks Inspector", "Editing marker timing and click behavior")
                }
            }
        }()

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(headerText.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                if let subtitle = headerText.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                InspectorSectionHeaderView(title: "Mode", accentRole: resolvedAccentRole)

                Picker("Mode", selection: $inspectorMode) {
                    ForEach(EditInspectorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            if inspectorMode == .suggestions || inspectorMode == .captureInfo {
                primaryContent
            } else if editorMode == .effects {
                effectsContent
            } else {
                primaryContent
            }
        }
    }
}

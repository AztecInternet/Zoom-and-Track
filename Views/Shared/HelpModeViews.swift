import SwiftUI

enum HelpTopic {
    case reviewTimeline
    case playbackPreview
    case zoomInspector
    case effectsInspector
    case captureTarget
    case captureComposition
    case captureSetup
    case libraryBrowser
    case libraryFilters

    var iconName: String {
        switch self {
        case .reviewTimeline:
            return "timeline.selection"
        case .playbackPreview:
            return "play.rectangle"
        case .zoomInspector:
            return "viewfinder"
        case .effectsInspector:
            return "slider.horizontal.3"
        case .captureTarget:
            return "macwindow.on.rectangle"
        case .captureComposition:
            return "rectangle.inset.filled"
        case .captureSetup:
            return "record.circle"
        case .libraryBrowser:
            return "folder"
        case .libraryFilters:
            return "line.3.horizontal.decrease.circle"
        }
    }

    var title: String {
        switch self {
        case .reviewTimeline:
            return "Timeline"
        case .playbackPreview:
            return "Playback Preview"
        case .zoomInspector:
            return "Zoom & Clicks Inspector"
        case .effectsInspector:
            return "Effects Inspector"
        case .captureTarget:
            return "Capture Target"
        case .captureComposition:
            return "Composition"
        case .captureSetup:
            return "Recording Setup"
        case .libraryBrowser:
            return "Library Browser"
        case .libraryFilters:
            return "Filters"
        }
    }

    var details: [String] {
        switch self {
        case .reviewTimeline:
            return [
                "Click the timeline to move playback.",
                "Drag markers to adjust timing.",
                "Pinch to zoom the timeline for precise editing.",
                "Two-finger drag horizontally to move around when zoomed in.",
                "The bottom readout shows the part of the timeline you are viewing.",
                "Hover over markers for timing details."
            ]
        case .playbackPreview:
            return [
                "Preview how the current edit will look.",
                "Use Click Focus to place a zoom target on the video.",
                "Drag the focus point to refine where the zoom lands.",
                "Move or resize effect areas directly on the video.",
                "A magnified preview appears while placing or dragging precise points."
            ]
        case .zoomInspector:
            return [
                "Lead In sets how early the move starts before the click.",
                "Zoom In controls how quickly the video moves into focus.",
                "Hold keeps the zoom on the target.",
                "Zoom Out controls the move back out.",
                "Choose the motion style and turn markers on or off as needed."
            ]
        case .effectsInspector:
            return [
                "Choose an effect style, then tune how it looks.",
                "Hold Start and Hold End set when the effect is strongest.",
                "Fade In and Fade Out control how the effect appears and clears.",
                "Region controls shape the effect area and soften its edge.",
                "Turn effect markers on or off without deleting them."
            ]
        case .captureTarget:
            return [
                "Choose the display or window you want to record.",
                "Use Reload Targets if an app or display is missing.",
                "Screen Recording permission must be enabled before recording."
            ]
        case .captureComposition:
            return [
                "Choose the final shape of the video.",
                "Drag the preview or use arrow nudges to reframe the recording.",
                "Source Scale controls how much of the recording fills the frame."
            ]
        case .captureSetup:
            return [
                "Title, collection, project, and type help organise captures in the Library.",
                "Choose Output Folder changes where recordings are saved.",
                "Start Recording begins capturing the selected target.",
                "Stop Recording finishes the screen capture and opens it for editing."
            ]
        case .libraryBrowser:
            return [
                "Search by title, collection, project, or capture type.",
                "Select a capture to highlight it in the list.",
                "Double-click a capture to open it for editing.",
                "Reveal in Finder opens the saved recording location.",
                "Unavailable captures show a warning when the recording cannot be found."
            ]
        case .libraryFilters:
            return [
                "Collections and Projects narrow the capture list.",
                "Type chips filter by capture kind.",
                "Active filters appear above the list and can be removed individually.",
                "Reset clears all active filters."
            ]
        }
    }
}

struct HelpModeHintView: View {
    let topic: HelpTopic
    let isPresented: Bool
    let staggerIndex: Int
    @State private var isVisible = false
    @State private var presentationGeneration = 0

    init(topic: HelpTopic, isPresented: Bool = true, staggerIndex: Int = 0) {
        self.topic = topic
        self.isPresented = isPresented
        self.staggerIndex = staggerIndex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: topic.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(topic.title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(topic.details, id: \.self) { detail in
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.42), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1)
                .padding(1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 4)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.97, anchor: .top)
        .offset(y: isVisible ? 0 : 5)
        .allowsHitTesting(false)
        .onAppear {
            updatePresentation(animated: false)
        }
        .onChange(of: isPresented) {
            updatePresentation(animated: true)
        }
    }

    private var revealDelay: Double {
        min(Double(max(staggerIndex, 0)) * 0.075, 0.45)
    }

    private func updatePresentation(animated: Bool) {
        presentationGeneration += 1
        let generation = presentationGeneration

        guard isPresented else {
            let changes = { isVisible = false }
            if animated {
                withAnimation(.easeOut(duration: 0.18), changes)
            } else {
                changes()
            }
            return
        }

        isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) {
            guard presentationGeneration == generation, isPresented else { return }
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                isVisible = true
            }
        }
    }
}

struct HelpModeRegionHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.025))
            )
            .allowsHitTesting(false)
    }
}

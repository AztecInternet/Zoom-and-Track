import Foundation
import Observation

struct FlowTrackOnboardingState: Codable, Equatable {
    var schemaVersion: Int
    var completedStages: Set<FlowTrackOnboardingStage>
    var hasCompletedOnboarding: Bool
    var dismissedVersion: Int

    static let currentSchemaVersion = 1

    static var initial: FlowTrackOnboardingState {
        FlowTrackOnboardingState(
            schemaVersion: currentSchemaVersion,
            completedStages: [],
            hasCompletedOnboarding: false,
            dismissedVersion: 0
        )
    }
}

enum FlowTrackOnboardingStage: String, CaseIterable, Codable, Identifiable, Hashable {
    case captureTarget
    case captureSetup
    case startCapture
    case reviewBasics
    case timelineMarkers
    case markerInspector
    case smartSuggestions
    case export

    var id: String { rawValue }

    static let activeTourStages: [FlowTrackOnboardingStage] = [
        .captureTarget,
        .captureSetup,
        .timelineMarkers,
        .markerInspector,
        .smartSuggestions,
        .export
    ]

    var title: String {
        switch self {
        case .captureTarget:
            return "Choose what to capture"
        case .captureSetup:
            return "Set up the capture"
        case .startCapture:
            return "Start the capture"
        case .reviewBasics:
            return "Review your capture"
        case .timelineMarkers:
            return "Use the timeline"
        case .markerInspector:
            return "Adjust marker details"
        case .smartSuggestions:
            return "Review Smart Suggestions"
        case .export:
            return "Export the finished movie"
        }
    }

    var body: String {
        switch self {
        case .captureTarget:
            return "Pick the display or window you want to record. FlowTrack uses this source to create your editable capture."
        case .captureSetup:
            return "Check the framing, project details, and recording options before starting. These settings help keep your captures organised."
        case .startCapture:
            return "Press Start Recording when the target, framing, and project details are ready. FlowTrack will open the capture in Edit when recording finishes."
        case .reviewBasics:
            return "Use the preview and playback controls to check the recording before refining markers and effects."
        case .timelineMarkers:
            return "The timeline is where you check timing, scrub through the capture, and select markers. Each marker can be adjusted without changing the original recording."
        case .markerInspector:
            return "When a marker is selected, use the inspector to adjust zoom amount, timing, zoom type, click pulse, or effect settings."
        case .smartSuggestions:
            return "Smart Suggestions can help refine existing edits by reviewing timing and interaction patterns locally on your Mac."
        case .export:
            return "Create the final movie file after the review and edits are complete."
        }
    }

    var iconName: String {
        switch self {
        case .captureTarget:
            return "macwindow.on.rectangle"
        case .captureSetup:
            return "record.circle"
        case .startCapture:
            return "record.circle.fill"
        case .reviewBasics:
            return "play.rectangle"
        case .timelineMarkers:
            return "timeline.selection"
        case .markerInspector:
            return "slider.horizontal.3"
        case .smartSuggestions:
            return "sparkles"
        case .export:
            return "square.and.arrow.up"
        }
    }

    var stageIndex: Int {
        Self.activeTourStages.firstIndex(of: self) ?? 0
    }

    var progressIndex: Int {
        stageIndex + 1
    }

    var progressCount: Int {
        Self.activeTourStages.count
    }

    var nextStage: FlowTrackOnboardingStage? {
        let nextIndex = stageIndex + 1
        guard Self.activeTourStages.indices.contains(nextIndex) else { return nil }
        return Self.activeTourStages[nextIndex]
    }

    var previousStage: FlowTrackOnboardingStage? {
        let previousIndex = stageIndex - 1
        guard Self.activeTourStages.indices.contains(previousIndex) else { return nil }
        return Self.activeTourStages[previousIndex]
    }
}

struct FlowTrackOnboardingStore {
    private enum Key {
        static let schemaVersion = "FlowTrackOnboarding.schemaVersion"
        static let completedStages = "FlowTrackOnboarding.completedStages"
        static let hasCompleted = "FlowTrackOnboarding.hasCompleted"
        static let dismissedVersion = "FlowTrackOnboarding.dismissedVersion"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadState() -> FlowTrackOnboardingState {
        let storedSchemaVersion = userDefaults.integer(forKey: Key.schemaVersion)
        guard storedSchemaVersion == 0 || storedSchemaVersion == FlowTrackOnboardingState.currentSchemaVersion else {
            return .initial
        }

        let completedStages = Set(
            userDefaults.stringArray(forKey: Key.completedStages)?
                .compactMap(FlowTrackOnboardingStage.init(rawValue:)) ?? []
        )

        return FlowTrackOnboardingState(
            schemaVersion: FlowTrackOnboardingState.currentSchemaVersion,
            completedStages: completedStages,
            hasCompletedOnboarding: userDefaults.bool(forKey: Key.hasCompleted),
            dismissedVersion: userDefaults.integer(forKey: Key.dismissedVersion)
        )
    }

    func saveState(_ state: FlowTrackOnboardingState) {
        userDefaults.set(FlowTrackOnboardingState.currentSchemaVersion, forKey: Key.schemaVersion)
        userDefaults.set(sortedStageIDs(from: state.completedStages), forKey: Key.completedStages)
        userDefaults.set(state.hasCompletedOnboarding, forKey: Key.hasCompleted)
        userDefaults.set(state.dismissedVersion, forKey: Key.dismissedVersion)
    }

    func reset() {
        userDefaults.removeObject(forKey: Key.schemaVersion)
        userDefaults.removeObject(forKey: Key.completedStages)
        userDefaults.removeObject(forKey: Key.hasCompleted)
        userDefaults.removeObject(forKey: Key.dismissedVersion)
    }

    private func sortedStageIDs(from stages: Set<FlowTrackOnboardingStage>) -> [String] {
        stages
            .sorted { $0.stageIndex < $1.stageIndex }
            .map(\.rawValue)
    }
}

@MainActor
@Observable
final class FlowTrackOnboardingManager {
    private let store: FlowTrackOnboardingStore
    private var state: FlowTrackOnboardingState

    private(set) var isPresented: Bool
    private(set) var currentStage: FlowTrackOnboardingStage?
    private(set) var completedStages: Set<FlowTrackOnboardingStage>
    private(set) var hasCompletedOnboarding: Bool
    private(set) var isFirstRunFlow: Bool
    private(set) var dismissedVersion: Int

    init(store: FlowTrackOnboardingStore? = nil) {
        let resolvedStore = store ?? FlowTrackOnboardingStore()
        self.store = resolvedStore
        let loadedState = resolvedStore.loadState()
        self.state = loadedState
        self.isPresented = false
        self.currentStage = nil
        self.completedStages = loadedState.completedStages
        self.hasCompletedOnboarding = loadedState.hasCompletedOnboarding
        self.isFirstRunFlow = false
        self.dismissedVersion = loadedState.dismissedVersion
    }

    func startFirstRunIfNeeded() {
        guard !hasCompletedOnboarding, !isPresented else { return }
        isFirstRunFlow = true
        currentStage = nextIncompleteStage() ?? FlowTrackOnboardingStage.activeTourStages.first
        isPresented = currentStage != nil
    }

    func startManualTour() {
        isFirstRunFlow = false
        currentStage = FlowTrackOnboardingStage.activeTourStages.first
        isPresented = currentStage != nil
    }

    func advance() {
        guard let currentStage else { return }
        markComplete(currentStage)

        if let nextStage = currentStage.nextStage {
            self.currentStage = nextStage
        } else {
            completeOnboarding()
        }
    }

    func back() {
        guard let currentStage else { return }
        self.currentStage = currentStage.previousStage ?? currentStage
    }

    func skip() {
        isPresented = false
        isFirstRunFlow = false
        currentStage = nil
        dismissedVersion = FlowTrackOnboardingState.currentSchemaVersion
        persistState()
    }

    func markComplete(_ stage: FlowTrackOnboardingStage) {
        completedStages.insert(stage)
        if FlowTrackOnboardingStage.activeTourStages.allSatisfy({ completedStages.contains($0) }) {
            hasCompletedOnboarding = true
        }
        persistState()
    }

    func reset() {
        store.reset()
        state = .initial
        isPresented = false
        currentStage = nil
        completedStages = []
        hasCompletedOnboarding = false
        isFirstRunFlow = false
        dismissedVersion = 0
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        isPresented = false
        isFirstRunFlow = false
        currentStage = nil
        persistState()
    }

    private func nextIncompleteStage() -> FlowTrackOnboardingStage? {
        FlowTrackOnboardingStage.activeTourStages.first { !completedStages.contains($0) }
    }

    private func persistState() {
        state = FlowTrackOnboardingState(
            schemaVersion: FlowTrackOnboardingState.currentSchemaVersion,
            completedStages: completedStages,
            hasCompletedOnboarding: hasCompletedOnboarding,
            dismissedVersion: dismissedVersion
        )
        store.saveState(state)
    }
}

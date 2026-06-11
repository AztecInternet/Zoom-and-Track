import CoreGraphics
import CoreML
import Foundation
import Vision

enum SmartSuggestionCoreMLUIElementType: String, CaseIterable {
    case sidebar
    case settingsPanel
    case form
    case dialog
    case dropdown
    case menu
    case toolbar
    case searchField
    case table
    case contentArea
    case unknown
}

enum SmartSuggestionCoreMLAnalysisSource: String {
    case mock
    case unavailable
    case coreML
}

struct SmartSuggestionCoreMLObservation {
    let regionID: String
    let frameTimestamp: Double
    let uiElementType: SmartSuggestionCoreMLUIElementType
    let confidence: Double
    let normalizedBounds: CGRect?
    let source: SmartSuggestionCoreMLAnalysisSource
    let modelName: String?
    let debugReason: String?
}

struct SmartSuggestionCoreMLDiagnostics {
    let isAvailable: Bool
    let modelName: String?
    let analyzedRegionCount: Int
    let analyzedFrameCount: Int
    let observationCount: Int
    let averageConfidence: Double
    let source: SmartSuggestionCoreMLAnalysisSource
    let debugReason: String?
    let elapsedSeconds: Double
}

struct SmartSuggestionCoreMLAnalysisResult {
    let observations: [SmartSuggestionCoreMLObservation]
    let diagnostics: SmartSuggestionCoreMLDiagnostics
}

struct SmartSuggestionCoreMLAnalysisService {
    private struct LoadedModel {
        let model: VNCoreMLModel
        let modelName: String
    }

    private let modelResourceName: String
    private let bundle: Bundle
    private let minimumConfidence = 0.01

    init(
        modelResourceName: String = "SmartSuggestionUIUnderstanding",
        bundle: Bundle = .main
    ) {
        self.modelResourceName = modelResourceName
        self.bundle = bundle
    }

    func analyzeUI(
        in samples: [ActivityRegionFrameSample],
        regions: [ActivityRegion]
    ) async -> SmartSuggestionCoreMLAnalysisResult {
        let startDate = Date()
        guard !Task.isCancelled else {
            return result(
                observations: [],
                isAvailable: false,
                modelName: nil,
                regionCount: regions.count,
                frameCount: samples.count,
                source: .unavailable,
                debugReason: "analysis cancelled before CoreML availability check",
                startDate: startDate
            )
        }

        guard let modelURL = bundledModelURL() else {
            return result(
                observations: [],
                isAvailable: false,
                modelName: nil,
                regionCount: regions.count,
                frameCount: samples.count,
                source: .unavailable,
                debugReason: "no bundled CoreML UI understanding model",
                startDate: startDate
            )
        }

        do {
            let loadedModel = try loadModel(from: modelURL)
            let observations = try analyzeSamples(
                samples,
                regions: regions,
                model: loadedModel
            )
            let analysisResult = result(
                observations: observations,
                isAvailable: true,
                modelName: loadedModel.modelName,
                regionCount: regions.count,
                frameCount: samples.count,
                source: .coreML,
                debugReason: nil,
                startDate: startDate
            )
            printDiagnostics(analysisResult.diagnostics)
            return analysisResult
        } catch {
            let analysisResult = result(
                observations: [],
                isAvailable: false,
                modelName: modelURL.deletingPathExtension().lastPathComponent,
                regionCount: regions.count,
                frameCount: samples.count,
                source: .unavailable,
                debugReason: "CoreML analysis unavailable: \(error.localizedDescription)",
                startDate: startDate
            )
            printDiagnostics(analysisResult.diagnostics)
            return analysisResult
        }
    }

    private func analyzeSamples(
        _ samples: [ActivityRegionFrameSample],
        regions: [ActivityRegion],
        model: LoadedModel
    ) throws -> [SmartSuggestionCoreMLObservation] {
        let regionsByID = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0) })
        var observations: [SmartSuggestionCoreMLObservation] = []

        for sample in samples {
            guard !Task.isCancelled else { break }
            let region = regionsByID[sample.regionID]
            let normalizedBounds = normalizedCropRect(for: region)
            let image = normalizedBounds.flatMap { crop(sample.image, to: $0) } ?? sample.image
            guard let classification = try classify(image: image, model: model) else { continue }
            observations.append(
                SmartSuggestionCoreMLObservation(
                    regionID: sample.regionID,
                    frameTimestamp: sample.actualTime,
                    uiElementType: uiElementType(for: classification.identifier),
                    confidence: classification.confidence,
                    normalizedBounds: normalizedBounds,
                    source: .coreML,
                    modelName: model.modelName,
                    debugReason: classification.identifier
                )
            )
        }

        return observations
    }

    private func classify(
        image: CGImage,
        model: LoadedModel
    ) throws -> (identifier: String, confidence: Double)? {
        var classificationObservation: VNClassificationObservation?
        var requestError: Error?
        let request = VNCoreMLRequest(model: model.model) { request, error in
            requestError = error
            classificationObservation = (request.results as? [VNClassificationObservation])?
                .sorted { lhs, rhs in lhs.confidence > rhs.confidence }
                .first
        }
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        if let requestError {
            throw requestError
        }
        guard let classificationObservation else { return nil }
        let confidence = clampedConfidence(Double(classificationObservation.confidence))
        guard confidence >= minimumConfidence else { return nil }
        return (classificationObservation.identifier, confidence)
    }

    private func loadModel(from url: URL) throws -> LoadedModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let modelURL = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        return LoadedModel(
            model: try VNCoreMLModel(for: model),
            modelName: url.deletingPathExtension().lastPathComponent
        )
    }

    private func result(
        observations: [SmartSuggestionCoreMLObservation],
        isAvailable: Bool,
        modelName: String?,
        regionCount: Int,
        frameCount: Int,
        source: SmartSuggestionCoreMLAnalysisSource,
        debugReason: String?,
        startDate: Date
    ) -> SmartSuggestionCoreMLAnalysisResult {
        SmartSuggestionCoreMLAnalysisResult(
            observations: observations,
            diagnostics: SmartSuggestionCoreMLDiagnostics(
                isAvailable: isAvailable,
                modelName: modelName,
                analyzedRegionCount: regionCount,
                analyzedFrameCount: frameCount,
                observationCount: observations.count,
                averageConfidence: averageConfidence(for: observations),
                source: source,
                debugReason: debugReason,
                elapsedSeconds: Date().timeIntervalSince(startDate)
            )
        )
    }

    private func bundledModelURL() -> URL? {
        let extensions = ["mlmodelc", "mlpackage", "mlmodel"]
        return extensions.compactMap { fileExtension in
            bundle.url(forResource: modelResourceName, withExtension: fileExtension)
        }.first
    }

    private func normalizedCropRect(for region: ActivityRegion?) -> CGRect? {
        guard let region,
              let normalizedArea = region.normalizedArea,
              !normalizedArea.isNull,
              !normalizedArea.isEmpty else {
            return nil
        }

        let padding = cropPadding(for: region)
        let paddedRect = normalizedArea.insetBy(dx: -padding, dy: -padding)
        let minimumSize = minimumCropSize(for: region)
        let expandedRect = CGRect(
            x: paddedRect.midX - max(paddedRect.width, minimumSize.width) / 2,
            y: paddedRect.midY - max(paddedRect.height, minimumSize.height) / 2,
            width: max(paddedRect.width, minimumSize.width),
            height: max(paddedRect.height, minimumSize.height)
        )
        let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let cropRect = expandedRect.intersection(unitRect)
        return cropRect.isNull || cropRect.isEmpty ? nil : cropRect
    }

    private func cropPadding(for region: ActivityRegion) -> CGFloat {
        switch region.kind {
        case .click:
            return 0.16
        case .clickSequence:
            return 0.18
        case .pause, .repeatedArea:
            return 0.22
        case .unknown:
            return 0.20
        }
    }

    private func minimumCropSize(for region: ActivityRegion) -> CGSize {
        switch region.kind {
        case .click:
            return CGSize(width: 0.34, height: 0.28)
        case .clickSequence:
            return CGSize(width: 0.42, height: 0.34)
        case .pause, .repeatedArea:
            return CGSize(width: 0.48, height: 0.40)
        case .unknown:
            return CGSize(width: 0.44, height: 0.36)
        }
    }

    private func crop(_ image: CGImage, to normalizedRect: CGRect) -> CGImage? {
        let imageRect = CGRect(
            x: CGFloat(image.width) * normalizedRect.minX,
            y: CGFloat(image.height) * normalizedRect.minY,
            width: CGFloat(image.width) * normalizedRect.width,
            height: CGFloat(image.height) * normalizedRect.height
        )
        let clampedRect = imageRect
            .intersection(CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
            .integral
        guard clampedRect.width >= 8, clampedRect.height >= 8 else { return nil }
        return image.cropping(to: clampedRect)
    }

    private func uiElementType(for identifier: String) -> SmartSuggestionCoreMLUIElementType {
        let normalizedIdentifier = identifier
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        if normalizedIdentifier.contains("sidebar") || normalizedIdentifier.contains("side bar") {
            return .sidebar
        }
        if normalizedIdentifier.contains("settings") || normalizedIdentifier.contains("preference") {
            return .settingsPanel
        }
        if normalizedIdentifier.contains("toolbar") || normalizedIdentifier.contains("tool bar") {
            return .toolbar
        }
        if normalizedIdentifier.contains("dropdown") || normalizedIdentifier.contains("drop down") || normalizedIdentifier.contains("popup") {
            return .dropdown
        }
        if normalizedIdentifier.contains("menu") {
            return .menu
        }
        if normalizedIdentifier.contains("dialog") || normalizedIdentifier.contains("modal") || normalizedIdentifier.contains("alert") {
            return .dialog
        }
        if normalizedIdentifier.contains("form") || normalizedIdentifier.contains("field") || normalizedIdentifier.contains("input") {
            return .form
        }
        if normalizedIdentifier.contains("search") {
            return .searchField
        }
        if normalizedIdentifier.contains("table") || normalizedIdentifier.contains("list") {
            return .table
        }
        if normalizedIdentifier.contains("content") || normalizedIdentifier.contains("editor") || normalizedIdentifier.contains("canvas") || normalizedIdentifier.contains("workspace") {
            return .contentArea
        }
        return .unknown
    }

    private func averageConfidence(for observations: [SmartSuggestionCoreMLObservation]) -> Double {
        guard !observations.isEmpty else { return 0 }
        let total = observations.reduce(0) { partialResult, observation in
            partialResult + observation.confidence
        }
        return total / Double(observations.count)
    }

    private func clampedConfidence(_ confidence: Double) -> Double {
        min(max(confidence, 0), 1)
    }

    private func printDiagnostics(_ diagnostics: SmartSuggestionCoreMLDiagnostics) {
        let modelName = diagnostics.modelName ?? "none"
        let averageConfidence = String(format: "%.2f", diagnostics.averageConfidence)
        print("[SmartSuggestionCoreML] available=\(diagnostics.isAvailable) model=\(modelName) regions=\(diagnostics.analyzedRegionCount) frames=\(diagnostics.analyzedFrameCount) observations=\(diagnostics.observationCount) averageConfidence=\(averageConfidence)")
    }
}

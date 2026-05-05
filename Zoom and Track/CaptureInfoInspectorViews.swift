import SwiftUI

extension ContentView {
    func captureInfoInspector(_ summary: RecordingInspectionSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title / Short Description")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Untitled Capture", text: $captureInfoTitleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    focusedCaptureInfoField == .title ? Color.accentColor.opacity(0.32) : Color.secondary.opacity(0.14),
                                    lineWidth: 1
                                )
                        )
                        .focused($focusedCaptureInfoField, equals: .title)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Collection")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Default Collection", text: $captureInfoCollectionDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    focusedCaptureInfoField == .collection ? Color.accentColor.opacity(0.32) : Color.secondary.opacity(0.14),
                                    lineWidth: 1
                                )
                        )
                        .focused($focusedCaptureInfoField, equals: .collection)
                        .overlay(alignment: .topLeading) {
                            if focusedCaptureInfoField == .collection,
                               !collectionAutocompleteSuggestions.isEmpty {
                                autocompleteSuggestionPanel(
                                    suggestions: collectionAutocompleteSuggestions,
                                    selectionAction: selectCollectionSuggestion
                                )
                                .offset(y: 34)
                            }
                        }
                }
                .zIndex(focusedCaptureInfoField == .collection ? 2 : 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Project")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("General Project", text: $captureInfoProjectDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    focusedCaptureInfoField == .project ? Color.accentColor.opacity(0.32) : Color.secondary.opacity(0.14),
                                    lineWidth: 1
                                )
                        )
                        .focused($focusedCaptureInfoField, equals: .project)
                        .overlay(alignment: .topLeading) {
                            if focusedCaptureInfoField == .project,
                               !projectAutocompleteSuggestions.isEmpty {
                                autocompleteSuggestionPanel(
                                    suggestions: projectAutocompleteSuggestions,
                                    selectionAction: selectProjectSuggestion
                                )
                                .offset(y: 34)
                            }
                        }
                }
                .zIndex(focusedCaptureInfoField == .project ? 2 : 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Type")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    captureTypeChips(selectedType: viewModel.captureType)
                }

                Divider()

                metadataItem("Created", summary.createdAt.formatted(date: .abbreviated, time: .shortened))

                if let duration = summary.duration {
                    metadataItem("Duration", String(format: "%.2fs", duration))
                }

                metadataItem("Bundle Path", summary.bundleURL.path, multiline: true)

                Button("Reveal in Finder") {
                    viewModel.revealInFinder()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            syncCaptureInfoDrafts(from: summary, force: true)
        }
        .onChange(of: summary.captureID) {
            syncCaptureInfoDrafts(from: summary, force: true)
        }
        .onChange(of: summary.updatedAt) {
            syncCaptureInfoDrafts(from: summary)
        }
        .onChange(of: focusedCaptureInfoField) {
            guard focusedCaptureInfoField == nil else { return }
            syncCaptureInfoDrafts(from: summary, force: true)
        }
        .onChange(of: captureInfoTitleDraft) {
            viewModel.setCurrentCaptureTitle(captureInfoTitleDraft)
        }
        .onChange(of: captureInfoCollectionDraft) {
            viewModel.setCurrentCaptureCollectionName(captureInfoCollectionDraft)
        }
        .onChange(of: captureInfoProjectDraft) {
            viewModel.setCurrentCaptureProjectName(captureInfoProjectDraft)
        }
    }

    func syncCaptureInfoDrafts(from summary: RecordingInspectionSummary, force: Bool = false) {
        if force || focusedCaptureInfoField != .title {
            captureInfoTitleDraft = viewModel.captureTitle
        }
        if force || focusedCaptureInfoField != .collection {
            captureInfoCollectionDraft = viewModel.collectionName
        }
        if force || focusedCaptureInfoField != .project {
            captureInfoProjectDraft = viewModel.projectName
        }
    }

    var collectionAutocompleteSuggestions: [String] {
        autocompleteSuggestions(
            from: viewModel.libraryItems
                .map(\.collectionName)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            matching: captureInfoCollectionDraft
        )
    }

    var projectAutocompleteSuggestions: [String] {
        let query = captureInfoProjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        let preferredCollection = captureInfoCollectionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = viewModel.libraryItems

        let preferredProjects = autocompleteSuggestions(
            from: items
                .filter { preferredCollection.isEmpty ? false : $0.collectionName.compare(preferredCollection, options: .caseInsensitive) == .orderedSame }
                .map(\.projectName)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            matching: query
        )

        if preferredProjects.count >= 6 {
            return Array(preferredProjects.prefix(6))
        }

        let allProjects = autocompleteSuggestions(
            from: items
                .map(\.projectName)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            matching: query
        )

        var combined = preferredProjects
        for project in allProjects where !combined.contains(where: { $0.compare(project, options: .caseInsensitive) == .orderedSame }) {
            combined.append(project)
            if combined.count == 6 {
                break
            }
        }
        return combined
    }

    func autocompleteSuggestions(from values: [String], matching query: String) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let uniqueValues = Array(Set(values)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        return uniqueValues
            .filter { value in
                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedValue.isEmpty else { return false }
                if trimmedQuery.isEmpty {
                    return true
                }
                guard trimmedValue.compare(trimmedQuery, options: .caseInsensitive) != .orderedSame else { return false }
                return trimmedValue.localizedCaseInsensitiveContains(trimmedQuery)
            }
            .prefix(6)
            .map { $0 }
    }

    func selectCollectionSuggestion(_ suggestion: String) {
        captureInfoCollectionDraft = suggestion
        viewModel.setCurrentCaptureCollectionName(suggestion)
        focusedCaptureInfoField = nil
    }

    func selectProjectSuggestion(_ suggestion: String) {
        captureInfoProjectDraft = suggestion
        viewModel.setCurrentCaptureProjectName(suggestion)
        focusedCaptureInfoField = nil
    }

    func autocompleteSuggestionPanel(
        suggestions: [String],
        selectionAction: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    selectionAction(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < suggestions.count - 1 {
                    Divider()
                        .opacity(0.35)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.94))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    func captureTypeChips(selectedType: CaptureType) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(CaptureType.allCases) { type in
                Button {
                    viewModel.setCurrentCaptureType(type)
                } label: {
                    Text(type.displayName)
                        .font(.system(size: 12, weight: selectedType == type ? .semibold : .medium))
                        .foregroundStyle(selectedType == type ? accentContrastingTextColor() : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedType == type ? Color.accentColor : Color.secondary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

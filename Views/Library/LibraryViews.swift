import SwiftUI

extension ContentView {
    var libraryView: some View {
        let filteredItems = filteredLibraryItems
        let resultSummary = "\(filteredItems.count) capture" + (filteredItems.count == 1 ? "" : "s")

        return VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Library",
                subtitle: viewModel.selectedOutputFolderPath ?? "Managed captures by Collection and Project",
                accentWidth: 132
            )

            HStack(spacing: 12) {
                librarySearchField
            }

            if let libraryStatusMessage = viewModel.libraryStatusMessage, !libraryStatusMessage.isEmpty {
                Text(libraryStatusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text(resultSummary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if hasActiveLibraryFilters {
                            Button("Reset Filters") {
                                clearLibraryFilters()
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 12, weight: .medium))
                        }
                    }

                    if hasActiveLibraryFilters {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if let selectedLibraryCollectionFilter {
                                    activeLibraryFilterChip(title: selectedLibraryCollectionFilter) {
                                        self.selectedLibraryCollectionFilter = nil
                                    }
                                }
                                if let selectedLibraryProjectFilter {
                                    activeLibraryFilterChip(title: selectedLibraryProjectFilter) {
                                        self.selectedLibraryProjectFilter = nil
                                    }
                                }
                                if let selectedLibraryTypeFilter {
                                    activeLibraryFilterChip(title: selectedLibraryTypeFilter.displayName) {
                                        self.selectedLibraryTypeFilter = nil
                                    }
                                }
                            }
                        }
                    }

                    if filteredItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No captures match current filters")
                                .font(.headline)
                            Text(hasActiveLibraryFilters ? "Try clearing one or more filters." : "Create a capture or adjust the library root in Settings.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(cardBackground)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(filteredItems) { item in
                                    libraryCaptureRow(item)
                                }
                            }
                            .padding(16)
                        }
                        .background(cardBackground)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                libraryFilterRail
                    .frame(width: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var filteredLibraryItems: [CaptureLibraryItem] {
        viewModel.libraryItems.filter { item in
            matchesLibrarySearch(item)
            && matchesLibraryCollectionFilter(item)
            && matchesLibraryProjectFilter(item)
            && matchesLibraryTypeFilter(item)
        }
    }

    func libraryCaptureRow(_ item: CaptureLibraryItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))

                Text("\(item.collectionName) • \(item.projectName)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.revealLibraryCapture(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.forward.folder.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Reveal in Finder")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                HStack(spacing: 10) {
                    libraryMetadataPill(text: item.captureType.displayName, systemName: "tag")
                    libraryMetadataPill(
                        text: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                        systemName: "calendar"
                    )
                    if let duration = item.duration {
                        libraryMetadataPill(
                            text: String(format: "%.2fs", duration),
                            systemName: "timer"
                        )
                    }
                }

                if !item.isAvailable, let statusMessage = item.statusMessage {
                    Label("\(item.status.displayName) • \(statusMessage)", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    viewModel.openLibraryCapture(item)
                    selectedTab = .review
                } label: {
                    Label("Edit Screen Capture", systemImage: "play.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(accentContrastingTextColor())
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .opacity(item.canOpenInEditor ? 1 : 0.45)
                .disabled(!item.canOpenInEditor)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    var librarySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search captures", text: $librarySearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !librarySearchText.isEmpty {
                Button {
                    librarySearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    func libraryMetadataPill(text: String, systemName: String) -> some View {
        Label(text, systemImage: systemName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
    }

    var hasActiveLibraryFilters: Bool {
        selectedLibraryCollectionFilter != nil || selectedLibraryProjectFilter != nil || selectedLibraryTypeFilter != nil
    }

    func matchesLibrarySearch(_ item: CaptureLibraryItem) -> Bool {
        let query = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = [
            item.title,
            item.collectionName,
            item.projectName,
            item.captureType.displayName
        ].joined(separator: " ").localizedLowercase
        return haystack.contains(query.localizedLowercase)
    }

    func matchesLibraryCollectionFilter(_ item: CaptureLibraryItem) -> Bool {
        guard let selectedLibraryCollectionFilter else { return true }
        return item.collectionName == selectedLibraryCollectionFilter
    }

    func matchesLibraryProjectFilter(_ item: CaptureLibraryItem) -> Bool {
        guard let selectedLibraryProjectFilter else { return true }
        return item.projectName == selectedLibraryProjectFilter
    }

    func matchesLibraryTypeFilter(_ item: CaptureLibraryItem) -> Bool {
        guard let selectedLibraryTypeFilter else { return true }
        return item.captureType == selectedLibraryTypeFilter
    }

    var libraryFilterRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Drill Down")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if hasActiveLibraryFilters {
                        Button("Reset") {
                            clearLibraryFilters()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .medium))
                    }
                }

                libraryFilterSection(
                    title: "Collections",
                    options: libraryCollectionOptions,
                    selectedValue: selectedLibraryCollectionFilter,
                    action: toggleLibraryCollectionFilter
                )

                libraryFilterSection(
                    title: "Projects",
                    options: libraryProjectOptions,
                    selectedValue: selectedLibraryProjectFilter,
                    action: toggleLibraryProjectFilter
                )

                libraryTypeSection
            }
            .padding(18)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    var libraryCollectionOptions: [LibraryFilterOption] {
        buildLibraryFilterOptions(
            from: viewModel.libraryItems.filter { item in
                matchesLibrarySearch(item)
                && matchesLibraryProjectFilter(item)
                && matchesLibraryTypeFilter(item)
            },
            value: \.collectionName
        )
    }

    var libraryProjectOptions: [LibraryFilterOption] {
        buildLibraryFilterOptions(
            from: viewModel.libraryItems.filter { item in
                matchesLibrarySearch(item)
                && matchesLibraryCollectionFilter(item)
                && matchesLibraryTypeFilter(item)
            },
            value: \.projectName
        )
    }

    var libraryTypeOptions: [CaptureType: Int] {
        let items = viewModel.libraryItems.filter { item in
            matchesLibrarySearch(item)
            && matchesLibraryCollectionFilter(item)
            && matchesLibraryProjectFilter(item)
        }
        return Dictionary(items.map { ($0.captureType, 1) }, uniquingKeysWith: +)
    }

    func buildLibraryFilterOptions(
        from items: [CaptureLibraryItem],
        value: KeyPath<CaptureLibraryItem, String>
    ) -> [LibraryFilterOption] {
        let counts = Dictionary(items.map { ($0[keyPath: value], 1) }, uniquingKeysWith: +)
        return counts.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { key in
            LibraryFilterOption(label: key, count: counts[key] ?? 0)
        }
    }

    func libraryFilterSection(
        title: String,
        options: [LibraryFilterOption],
        selectedValue: String?,
        action: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if options.isEmpty {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(options) { option in
                        Button {
                            action(option.label)
                        } label: {
                            HStack(spacing: 10) {
                                Text(option.label)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(option.count)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12, weight: selectedValue == option.label ? .semibold : .medium))
                            .foregroundStyle(selectedValue == option.label ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedValue == option.label ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selectedValue == option.label ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var libraryTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Types")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(CaptureType.allCases) { type in
                    if let count = libraryTypeOptions[type], count > 0 {
                        Button {
                            toggleLibraryTypeFilter(type)
                        } label: {
                            HStack(spacing: 6) {
                                Text(type.displayName)
                                    .lineLimit(1)
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .font(.system(size: 12, weight: selectedLibraryTypeFilter == type ? .semibold : .medium))
                            .foregroundStyle(selectedLibraryTypeFilter == type ? Color.white : Color.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedLibraryTypeFilter == type ? Color.accentColor : Color.secondary.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    func activeLibraryFilterChip(title: String, removeAction: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        )
    }

    func toggleLibraryCollectionFilter(_ collectionName: String) {
        if selectedLibraryCollectionFilter == collectionName {
            selectedLibraryCollectionFilter = nil
        } else {
            selectedLibraryCollectionFilter = collectionName
            if let currentProjectFilter = selectedLibraryProjectFilter,
               !viewModel.libraryItems.contains(where: { $0.collectionName == collectionName && $0.projectName == currentProjectFilter }) {
                selectedLibraryProjectFilter = nil
            }
        }
    }

    func toggleLibraryProjectFilter(_ projectName: String) {
        if selectedLibraryProjectFilter == projectName {
            selectedLibraryProjectFilter = nil
        } else {
            selectedLibraryProjectFilter = projectName
        }
    }

    func toggleLibraryTypeFilter(_ type: CaptureType) {
        selectedLibraryTypeFilter = selectedLibraryTypeFilter == type ? nil : type
    }

    func clearLibraryFilters() {
        selectedLibraryCollectionFilter = nil
        selectedLibraryProjectFilter = nil
        selectedLibraryTypeFilter = nil
    }
}

import SwiftUI

// MARK: - Filter model

enum FilterMode: String, CaseIterable, Identifiable {
    case minimum = "Minimum"
    case maximum = "Maximum"
    case exactly = "Exactly"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .minimum: return .red
        case .maximum: return .green
        case .exactly: return .orange
        }
    }
}

enum FilterField: String, CaseIterable, Identifiable {
    case rating = "Rating"
    case weight = "Complexity"
    case playtime = "Playtime"
    case players = "Players"
    case yearPublished = "Year Published"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rating: return "star"
        case .weight: return "scalemass"
        case .playtime: return "clock"
        case .players: return "person.2"
        case .yearPublished: return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .rating: return .yellow
        case .weight: return .purple
        case .playtime: return .blue
        case .players: return .green
        case .yearPublished: return .orange
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .rating: return 1...10
        case .weight: return 1...5
        case .playtime: return 15...300
        case .players: return 1...10
        case .yearPublished: return 1970...2026
        }
    }

    var step: Double {
        switch self {
        case .rating: return 0.5
        case .weight: return 0.1
        case .playtime: return 15
        case .players, .yearPublished: return 1
        }
    }

    var unit: String? {
        switch self {
        case .playtime: return "min"
        default: return nil
        }
    }

    var isInteger: Bool {
        switch self {
        case .playtime, .players, .yearPublished: return true
        default: return false
        }
    }

    var defaultValue: Double {
        switch self {
        case .rating: return 7
        case .weight: return 3
        case .playtime: return 60
        case .players: return 4
        case .yearPublished: return 2015
        }
    }

    func formatValue(_ v: Double) -> String {
        isInteger ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

struct FilterSpec: Equatable {
    var mode: FilterMode
    var value: Double
}

enum TitleMatch: String, CaseIterable, Identifiable {
    case include = "Include"
    case exclude = "Exclude"
    var id: String { rawValue }
}

// BGG language-dependence poll levels (1–5).
enum LanguageDependence: Int, CaseIterable, Identifiable {
    case none = 1, some, moderate, extensive, unplayable
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "No necessary in-game text"
        case .some: return "Some necessary text"
        case .moderate: return "Moderate in-game text"
        case .extensive: return "Extensive use of text"
        case .unplayable: return "All in-game text necessary"
        }
    }

    var subtitle: String {
        switch self {
        case .none: return "Can be played in any language."
        case .some: return "Easy to recall or needs a small cheat sheet."
        case .moderate: return "Needs a reference sheet or translated aids."
        case .extensive: return "Massive conversion needed to be playable."
        case .unplayable: return "Unplayable in another language."
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle"
        case .some: return "triangle"
        case .moderate: return "diamond"
        case .extensive: return "pentagon"
        case .unplayable: return "hexagon"
        }
    }

    var color: Color {
        switch self {
        case .none: return .green
        case .some: return Color(red: 0.5, green: 0.82, blue: 0.1)  // lime, distinct from none
        case .moderate: return .yellow
        case .extensive: return .orange
        case .unplayable: return .red
        }
    }
}

struct GameFilters: Equatable {
    var specs: [FilterField: FilterSpec] = [:]
    var mechanics: Set<String> = []
    var languages: Set<Int> = []
    var titleQuery: String = ""
    var titleMode: TitleMatch = .include

    private var trimmedTitle: String { titleQuery.trimmingCharacters(in: .whitespaces) }

    var isEmpty: Bool {
        specs.isEmpty && mechanics.isEmpty && languages.isEmpty && trimmedTitle.isEmpty
    }
    var activeCount: Int {
        specs.count
            + (mechanics.isEmpty ? 0 : 1)
            + (languages.isEmpty ? 0 : 1)
            + (trimmedTitle.isEmpty ? 0 : 1)
    }

    func apply(_ games: [Game]) -> [Game] {
        guard !isEmpty else { return games }
        return games.filter { passes($0) }
    }

    private func passes(_ game: Game) -> Bool {
        for (field, spec) in specs {
            if !fieldMatches(field, spec: spec, game: game) { return false }
        }
        if !mechanics.isEmpty, Set(game.mechanics ?? []).isDisjoint(with: mechanics) {
            return false
        }
        if !languages.isEmpty {
            guard let ld = game.languageDependence, languages.contains(ld) else { return false }
        }
        if !trimmedTitle.isEmpty {
            let contains = game.name.localizedCaseInsensitiveContains(trimmedTitle)
            if titleMode == .include, !contains { return false }
            if titleMode == .exclude, contains { return false }
        }
        return true
    }

    private func fieldMatches(_ field: FilterField, spec: FilterSpec, game: Game) -> Bool {
        func check(_ v: Double) -> Bool {
            switch spec.mode {
            case .minimum: return v >= spec.value
            case .maximum: return v <= spec.value
            case .exactly: return abs(v - spec.value) < 0.001
            }
        }

        switch field {
        case .rating:
            guard let v = game.rating else { return false }
            return check(v)
        case .weight:
            guard let v = game.weight else { return false }
            return check(v)
        case .playtime:
            guard let v = game.playtime else { return false }
            return check(Double(v))
        case .players:
            let mn = Double(game.minPlayers ?? 0)
            let mx = Double(game.maxPlayers ?? 0)
            switch spec.mode {
            case .minimum: return mx >= spec.value
            case .maximum: return mn <= spec.value
            case .exactly: return mn <= spec.value && spec.value <= mx
            }
        case .yearPublished:
            guard let v = game.yearPublished else { return false }
            return check(Double(v))
        }
    }
}

// MARK: - MechanicsPickerSheet

private struct MechanicsPickerSheet: View {
    @Binding var selected: Set<String>
    let mechanics: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    // Local mirror avoids @Binding inside ForEach closures (Swift 6.2 overload ambiguity)
    @State private var localSelected: Set<String> = []

    private func items() -> [String] {
        search.isEmpty ? mechanics : mechanics.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            mechanicsList()
                .navigationTitle("Mechanics")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { localSelected = selected }
                .searchable(text: $search, placement: .toolbar, prompt: "Search")
                .autocorrectionDisabled()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { selected = localSelected; dismiss() }.fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func mechanicsList() -> some View {
        let visible = items()
        if mechanics.isEmpty {
            ContentUnavailableView(
                "No Games in Collection",
                systemImage: "books.vertical",
                description: Text("Add games to use this filter.")
            )
        } else if visible.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visible, id: \.self) { (m: String) in
                        Button {
                            if localSelected.contains(m) { localSelected.remove(m) }
                            else { localSelected.insert(m) }
                        } label: {
                            HStack {
                                Text(m).foregroundStyle(.primary)
                                Spacer()
                                if localSelected.contains(m) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - FilterView

struct FilterView: View {
    @Binding var filters: GameFilters
    var availableMechanics: [String] = []
    @Environment(\.dismiss) private var dismiss
    @State private var exactInputs: [FilterField: String] = [:]
    @State private var mechanicsExpanded = false
    @State private var languageExpanded = false
    @State private var titleExpanded = false
    @State private var showMechanicsSheet = false

    private var enabledFields: [FilterField] { FilterField.allCases.filter { filters.specs[$0] != nil } }
    private var otherFields: [FilterField] { FilterField.allCases.filter { filters.specs[$0] == nil } }
    private var hasEnabledFilters: Bool { !enabledFields.isEmpty || mechanicsExpanded || languageExpanded || titleExpanded }
    private var hasOtherFilters: Bool { !otherFields.isEmpty || !mechanicsExpanded || !languageExpanded || !titleExpanded }

    var body: some View {
        NavigationStack {
            List {
                if hasEnabledFilters {
                    Section("Enabled filters") {
                        ForEach(enabledFields) { field in filterRow(field) }
                        if mechanicsExpanded { mechanicsRow }
                        if languageExpanded { languageFilterRow }
                        if titleExpanded { titleFilterRow }
                    }
                }
                if hasOtherFilters {
                    Section(hasEnabledFilters ? "Other filters" : "Select filters") {
                        ForEach(otherFields) { field in filterRow(field) }
                        if !mechanicsExpanded { mechanicsRow }
                        if !languageExpanded { languageFilterRow }
                        if !titleExpanded { titleFilterRow }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showMechanicsSheet) {
                MechanicsPickerSheet(selected: $filters.mechanics, mechanics: availableMechanics)
            }
            .onAppear {
                mechanicsExpanded = !filters.mechanics.isEmpty
                languageExpanded = !filters.languages.isEmpty
                titleExpanded = !filters.titleQuery.isEmpty
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear All") {
                        filters = GameFilters()
                        mechanicsExpanded = false
                        languageExpanded = false
                        titleExpanded = false
                    }
                    .foregroundStyle(.red)
                    .disabled(filters.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Numeric filter rows

    @ViewBuilder
    private func filterRow(_ field: FilterField) -> some View {
        let spec = filters.specs[field]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: field.icon)
                    .frame(width: 24)
                    .foregroundStyle(field.color)
                Text(field.rawValue).font(.subheadline)
                Spacer()
                Menu {
                    Button("Off") { filters.specs[field] = nil; exactInputs[field] = nil }
                    ForEach(FilterMode.allCases) { mode in
                        Button(mode.rawValue) {
                            let v = filters.specs[field]?.value ?? field.defaultValue
                            filters.specs[field] = FilterSpec(mode: mode, value: v)
                            exactInputs[field] = mode == .exactly ? field.formatValue(v) : nil
                        }
                    }
                } label: {
                    FilterMenuLabel(text: spec?.mode.rawValue ?? "Off")
                }
            }
            if let spec {
                if spec.mode == .exactly { exactlyInput(field) }
                else { sliderControl(field, spec: spec) }
            }
        }
        .padding(.vertical, spec != nil ? 4 : 0)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private struct FilterMenuLabel: View {
        let text: String
        var body: some View {
            HStack(spacing: 4) {
                Text(text)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.footnote.weight(.medium))
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func sliderControl(_ field: FilterField, spec: FilterSpec) -> some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { spec.value }, set: { filters.specs[field]?.value = $0 }),
                   in: field.range, step: field.step)
                .tint(spec.mode.color)
            HStack {
                Spacer()
                Text(field.formatValue(spec.value) + (field.unit.map { " \($0)" } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func exactlyInput(_ field: FilterField) -> some View {
        VStack(spacing: 4) {
            TextField("Value", text: Binding(
                get: { exactInputs[field] ?? field.formatValue(filters.specs[field]?.value ?? field.defaultValue) },
                set: { newVal in
                    exactInputs[field] = newVal
                    guard let d = Double(newVal), field.range.contains(d) else { return }
                    filters.specs[field]?.value = d
                }
            ))
            .keyboardType(field.isInteger ? .numberPad : .decimalPad)
            .font(.system(size: 52, weight: .semibold))
            .multilineTextAlignment(.center)
            if let unit = field.unit {
                Text(unit).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Mechanics row

    private var mechanicsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "gearshape.2").frame(width: 24).foregroundStyle(.indigo)
                Text("Mechanics").font(.subheadline)
                Spacer()
                Menu {
                    Button("Off") { mechanicsExpanded = false; filters.mechanics = [] }
                    Button("Select") { mechanicsExpanded = true }
                } label: {
                    FilterMenuLabel(text: mechanicsExpanded ? (filters.mechanics.isEmpty ? "Select" : "\(filters.mechanics.count) on") : "Off")
                }
            }
            if mechanicsExpanded {
                Button {
                    showMechanicsSheet = true
                } label: {
                    HStack {
                        Text(filters.mechanics.isEmpty ? "Select mechanics…" : filters.mechanics.sorted().joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(filters.mechanics.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, mechanicsExpanded ? 4 : 0)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    // MARK: - Language dependency row

    private var languageFilterRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "character.book.closed").frame(width: 24).foregroundStyle(.teal)
                Text("Language Dependency").font(.subheadline)
                Spacer()
                Menu {
                    Button("Off") { languageExpanded = false; filters.languages = [] }
                    Button("Select") { languageExpanded = true }
                } label: {
                    FilterMenuLabel(text: languageExpanded ? (filters.languages.isEmpty ? "Select" : "\(filters.languages.count) on") : "Off")
                }
            }
            if languageExpanded {
                VStack(spacing: 0) {
                    ForEach(LanguageDependence.allCases) { ld in
                        languageOptionRow(ld)
                        if ld.rawValue < LanguageDependence.allCases.last!.rawValue {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.vertical, languageExpanded ? 4 : 0)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private func languageOptionRow(_ ld: LanguageDependence) -> some View {
        let on = filters.languages.contains(ld.rawValue)
        return Button {
            if filters.languages.contains(ld.rawValue) {
                filters.languages.remove(ld.rawValue)
            } else {
                filters.languages.insert(ld.rawValue)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: ld.icon)
                    .font(.system(size: 18))
                    .frame(width: 24)
                    .foregroundStyle(on ? ld.color : ld.color.opacity(0.35))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ld.title).font(.subheadline.weight(on ? .semibold : .regular))
                    Text(ld.subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(on ? ld.color : Color.secondary.opacity(0.2))
                        .frame(width: 22, height: 22)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Title row

    private var titleFilterRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "textformat").frame(width: 24).foregroundStyle(.pink)
                Text("Title").font(.subheadline)
                Spacer()
                Menu {
                    Button("Off") { titleExpanded = false; filters.titleQuery = "" }
                    ForEach(TitleMatch.allCases) { m in
                        Button(m.rawValue) { titleExpanded = true; filters.titleMode = m }
                    }
                } label: {
                    FilterMenuLabel(text: titleExpanded ? filters.titleMode.rawValue : "Off")
                }
            }
            if titleExpanded {
                HStack(spacing: 8) {
                    TextField("Type to filter…", text: $filters.titleQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    Button {
                        titleExpanded = false
                        dismiss()
                    } label: {
                        Text("Confirm")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(filters.titleQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(filters.titleQuery.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
            }
        }
        .padding(.vertical, titleExpanded ? 4 : 0)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    // MARK: - Shared
}

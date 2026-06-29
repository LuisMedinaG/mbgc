import SwiftUI

// MARK: - Filter model

enum FilterMode: String, CaseIterable, Identifiable, Codable {
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

enum FilterField: String, CaseIterable, Identifiable, Codable {
    case rating        = "Rating"
    case userRating    = "My Rating"
    case weight        = "Complexity"
    case playtime      = "Playtime"
    case players       = "Players"
    case bestFor       = "Best For"
    case bggRank       = "BGG Rank"
    case yearPublished = "Year Published"
    case timesPlayed   = "Times Played"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rating:        return "star"
        case .userRating:    return "star.fill"
        case .weight:        return "scalemass"
        case .playtime:      return "clock"
        case .players:       return "person.2"
        case .bestFor:       return "person.2.circle"
        case .bggRank:       return "trophy"
        case .yearPublished: return "calendar"
        case .timesPlayed:   return "clock.arrow.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .rating:        return .yellow
        case .userRating:    return .orange
        case .weight:        return .purple
        case .playtime:      return .blue
        case .players:       return .green
        case .bestFor:       return .teal
        case .bggRank:       return .yellow
        case .yearPublished: return .orange
        case .timesPlayed:   return .teal
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .rating, .userRating: return 1...10
        case .weight:              return 1...5
        case .playtime:            return 15...300
        case .players, .bestFor:   return 1...10
        case .bggRank:             return 1...5000
        case .yearPublished:       return 1970...2026
        case .timesPlayed:         return 0...200
        }
    }

    var step: Double {
        switch self {
        case .rating, .userRating: return 0.5
        case .weight:              return 0.1
        case .playtime:            return 15
        case .bggRank:             return 50
        default:                   return 1
        }
    }

    var unit: String? {
        switch self {
        case .playtime: return "min"
        case .bestFor:  return "players"
        default:        return nil
        }
    }

    var isInteger: Bool {
        switch self {
        case .playtime, .players, .bestFor, .bggRank, .yearPublished, .timesPlayed:
            return true
        default:
            return false
        }
    }

    var defaultValue: Double {
        switch self {
        case .rating, .userRating: return 7
        case .weight:              return 3
        case .playtime:            return 60
        case .players, .bestFor:   return 4
        case .bggRank:             return 1000
        case .yearPublished:       return 2015
        case .timesPlayed:         return 5
        }
    }

    func formatValue(_ v: Double) -> String {
        isInteger ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

// MARK: - Checklist (set-based) filter fields

enum SetFilterField: String, CaseIterable, Identifiable, Hashable, Codable {
    case designers  = "Designers"
    case artists    = "Artists"
    case publishers = "Publisher"
    case types      = "Types"
    case categories = "Categories"
    case mechanics  = "Mechanics"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .designers:  return "pencil.and.ruler"
        case .artists:    return "paintpalette"
        case .publishers: return "building.2"
        case .types:      return "square.grid.2x2"
        case .categories: return "tag"
        case .mechanics:  return "gearshape"
        }
    }

    var color: Color {
        switch self {
        case .designers:  return .cyan
        case .artists:    return .pink
        case .publishers: return .brown
        case .types:      return .indigo
        case .categories: return .teal
        case .mechanics:  return .mint
        }
    }

    func values(from games: [Game]) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for game in games {
            for v in gameValues(game) { counts[v, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    func gameValues(_ game: Game) -> [String] {
        switch self {
        case .designers:  return game.designers ?? []
        case .artists:    return game.artists ?? []
        case .publishers: return game.publishers ?? []
        case .types:      return game.types ?? []
        case .categories: return game.categories ?? []
        case .mechanics:  return game.mechanics ?? []
        }
    }
}

// MARK: - Language dependence levels

struct LangLevel: Identifiable {
    let level: Int
    let title: String
    let subtitle: String
    let color: Color
    let symbol: String
    var id: Int { level }
}

let langLevels: [LangLevel] = [
    LangLevel(level: 1, title: "No necessary in-game text",  subtitle: "Can be played in any language.",                      color: .green,                               symbol: "circle"),
    LangLevel(level: 2, title: "Some necessary text",         subtitle: "Easy to recall or needs a small cheat sheet.",        color: .green,                               symbol: "triangle"),
    LangLevel(level: 3, title: "Moderate in-game text",       subtitle: "Needs a reference sheet or translated aids.",         color: Color(red: 0.75, green: 0.6, blue: 0), symbol: "diamond"),
    LangLevel(level: 4, title: "Extensive use of text",       subtitle: "Massive conversion needed to be playable.",           color: Color(red: 0.85, green: 0.45, blue: 0), symbol: "pentagon"),
    LangLevel(level: 5, title: "All in-game text necessary",  subtitle: "Unplayable in another language.",                     color: .red,                                 symbol: "hexagon"),
]

// MARK: - Filter spec

struct FilterSpec: Equatable, Codable {
    var mode: FilterMode
    var value: Double
}

// MARK: - GameFilters

struct GameFilters: Equatable, Codable {
    var specs: [FilterField: FilterSpec] = [:]
    var setFilters: [SetFilterField: Set<String>] = [:]
    var titleContains: String = ""
    var languageLevels: Set<Int> = []

    var isEmpty: Bool { specs.isEmpty && setFilters.isEmpty && titleContains.isEmpty && languageLevels.isEmpty }
    var activeCount: Int { specs.count + setFilters.count + (titleContains.isEmpty ? 0 : 1) + (languageLevels.isEmpty ? 0 : 1) }

    func apply(_ games: [Game]) -> [Game] {
        guard !isEmpty else { return games }
        return games.filter { passes($0) }
    }

    private func passes(_ game: Game) -> Bool {
        if !titleContains.isEmpty {
            let query = titleContains.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty, !game.name.localizedCaseInsensitiveContains(query) { return false }
        }
        if !languageLevels.isEmpty {
            guard let v = game.languageDependence, languageLevels.contains(v) else { return false }
        }
        for (field, selected) in setFilters {
            if !field.gameValues(game).contains(where: { selected.contains($0) }) { return false }
        }
        for (field, spec) in specs {
            if !fieldMatches(field, spec: spec, game: game) { return false }
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

        // Unknown values aren't filtered out — a missing field means "not enough info",
        // not "exclude". Keeps games visible when BGG lacks weight/rating/etc.
        switch field {
        case .rating:
            guard let v = game.rating else { return true }
            return check(v)
        case .userRating:
            guard let v = game.userRating else { return true }
            return check(v)
        case .weight:
            guard let v = game.weight else { return true }
            return check(v)
        case .playtime:
            guard let v = game.playtime else { return true }
            return check(Double(v))
        case .players:
            guard game.minPlayers != nil || game.maxPlayers != nil else { return true }
            let mn = Double(game.minPlayers ?? game.maxPlayers ?? 0)
            let mx = Double(game.maxPlayers ?? game.minPlayers ?? 0)
            switch spec.mode {
            case .minimum: return mx >= spec.value
            case .maximum: return mn <= spec.value
            case .exactly: return mn <= spec.value && spec.value <= mx
            }
        case .bestFor:
            guard let rp = game.recommendedPlayers, !rp.isEmpty else { return true }
            let n = Int(spec.value)
            switch spec.mode {
            case .minimum: return rp.contains { $0 >= n }
            case .maximum: return rp.contains { $0 <= n }
            case .exactly: return rp.contains(n)
            }
        case .bggRank:
            // Lower rank = better. "maximum 500" → top-500 games. Unranked games pass through.
            guard let v = game.bggRank else { return true }
            return check(Double(v))
        case .yearPublished:
            guard let v = game.yearPublished else { return true }
            return check(Double(v))
        case .timesPlayed:
            guard let v = game.numberOfPlays else { return true }
            return check(Double(v))
        }
    }
}

// MARK: - FilterRows (embeddable sections — used by FilterView and SmartListEditor)

/// Renders the enabled + other filter sections inline inside any List.
/// Parents own showTitlePicker and activeChecklist so sheets anchor outside the List.
struct FilterRows: View {
    @Binding var filters: GameFilters
    let games: [Game]
    @Binding var showTitlePicker: Bool
    @Binding var activeChecklist: SetFilterField?
    @State private var exactInputs: [FilterField: String] = [:]
    @State private var languageExpanded = false

    private var activeSets: [SetFilterField]  { SetFilterField.allCases.filter { filters.setFilters[$0] != nil } }
    private var inactiveSets: [SetFilterField] { SetFilterField.allCases.filter { filters.setFilters[$0] == nil } }
    private var activeNumeric: [FilterField]   { FilterField.allCases.filter { filters.specs[$0] != nil } }
    private var inactiveNumeric: [FilterField] { FilterField.allCases.filter { filters.specs[$0] == nil } }

    var body: some View {
        Group {
            if !filters.isEmpty {
                Section("Enabled filters") {
                    if !filters.titleContains.isEmpty { titleRow }
                    if !filters.languageLevels.isEmpty { languageDependenceRow }
                    ForEach(activeSets) { checklistRow($0) }
                    ForEach(activeNumeric) { filterRow($0) }
                }
            }
            Section(filters.isEmpty ? "Select filters" : "Other filters") {
                if filters.titleContains.isEmpty { titleRow }
                if filters.languageLevels.isEmpty { languageDependenceRow }
                ForEach(inactiveSets) { checklistRow($0) }
                ForEach(inactiveNumeric) { filterRow($0) }
            }
        }
        .onChange(of: filters.isEmpty) { _, isEmpty in
            if isEmpty { exactInputs.removeAll(); languageExpanded = false }
        }
    }

    // MARK: - Title row

    private var titleRow: some View {
        HStack {
            Image(systemName: "textformat.abc").frame(width: 24).foregroundStyle(Color.red)
            Text("Title contains").font(.body)
            Spacer()
            HStack(spacing: 3) {
                Text(filters.titleContains.isEmpty ? "Off" : "\"\(filters.titleContains)\"")
                    .foregroundStyle(filters.titleContains.isEmpty ? .secondary : Color.orange)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
        }
        .contentShape(Rectangle())
        .onTapGesture { showTitlePicker = true }
    }

    // MARK: - Language Dependence row

    private var languageDependenceRow: some View {
        let showOptions = languageExpanded || !filters.languageLevels.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "text.bubble").frame(width: 24).foregroundStyle(Color.indigo)
                Text("Language Dependence").font(.body)
                Spacer()
                Button { languageExpanded.toggle() } label: {
                    HStack(spacing: 3) {
                        Text(filters.languageLevels.isEmpty ? "Off" : "\(filters.languageLevels.count) selected")
                            .foregroundStyle(filters.languageLevels.isEmpty ? .secondary : Color.indigo)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 4)
                    .padding(.leading, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if showOptions {
                VStack(spacing: 6) {
                    ForEach(langLevels) { lvl in langLevelCard(lvl) }
                }
            }
        }
        .padding(.vertical, showOptions ? 4 : 0)
        .animation(.easeInOut(duration: 0.2), value: showOptions)
    }

    private func langLevelCard(_ lvl: LangLevel) -> some View {
        let isSelected = filters.languageLevels.contains(lvl.level)
        return HStack(spacing: 12) {
            Image(systemName: lvl.symbol)
                .font(.title3)
                .foregroundStyle(lvl.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(lvl.title).font(.subheadline.bold())
                Text(lvl.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.title3)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { filters.languageLevels.remove(lvl.level) }
            else { filters.languageLevels.insert(lvl.level) }
        }
    }

    // MARK: - Checklist row

    private func checklistRow(_ field: SetFilterField) -> some View {
        let selected = filters.setFilters[field]
        return HStack {
            Image(systemName: field.icon).frame(width: 24).foregroundStyle(field.color)
            Text(field.rawValue).font(.body)
            Spacer()
            HStack(spacing: 3) {
                Text(selected == nil ? "Off" : "\(selected!.count) selected")
                    .foregroundStyle(selected == nil ? .secondary : Color.orange)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
        }
        .contentShape(Rectangle())
        .onTapGesture { activeChecklist = field }
    }

    // MARK: - Numeric rows

    @ViewBuilder
    private func filterRow(_ field: FilterField) -> some View {
        let spec = filters.specs[field]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: field.icon).frame(width: 24).foregroundStyle(field.color)
                Text(field.rawValue).font(.body)
                Spacer()
                modeMenu(field, spec: spec)
            }
            if let spec {
                if spec.mode == .exactly { exactlyInput(field) }
                else { sliderControl(field, spec: spec) }
            }
        }
        .padding(.vertical, spec != nil ? 4 : 0)
        .animation(.easeInOut(duration: 0.2), value: spec != nil)
    }

    private func modeMenu(_ field: FilterField, spec: FilterSpec?) -> some View {
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
            HStack(spacing: 3) {
                Text(spec?.mode.rawValue ?? "Off").foregroundStyle(spec?.mode.color ?? .secondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.vertical, 4)
            .padding(.leading, 8)
            .contentShape(Rectangle())
        }
    }

    private func sliderControl(_ field: FilterField, spec: FilterSpec) -> some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(get: { spec.value }, set: { filters.specs[field]?.value = $0 }),
                in: field.range, step: field.step
            )
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
            TextField(
                "Value",
                text: Binding(
                    get: { exactInputs[field] ?? field.formatValue(filters.specs[field]?.value ?? field.defaultValue) },
                    set: { newVal in
                        exactInputs[field] = newVal
                        guard let d = Double(newVal), field.range.contains(d) else { return }
                        filters.specs[field]?.value = d
                    }
                )
            )
            .keyboardType(field.isInteger ? .numberPad : .decimalPad)
            .font(.system(size: 52, weight: .semibold))
            .multilineTextAlignment(.center)
            if let unit = field.unit { Text(unit).font(.callout).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - FilterView (modal wrapper around FilterRows)

struct FilterView: View {
    @Binding var filters: GameFilters
    let games: [Game]
    @Environment(\.dismiss) private var dismiss
    @State private var showTitlePicker = false
    @State private var activeChecklist: SetFilterField?

    var body: some View {
        NavigationStack {
            List {
                FilterRows(filters: $filters, games: games, showTitlePicker: $showTitlePicker, activeChecklist: $activeChecklist)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear All") { filters = GameFilters() }
                        .foregroundStyle(.red)
                        .disabled(filters.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(item: $activeChecklist) { field in
                ChecklistPickerSheet(
                    title: field.rawValue,
                    options: field.values(from: games),
                    selected: Binding(
                        get: { filters.setFilters[field] ?? [] },
                        set: { filters.setFilters[field] = $0.isEmpty ? nil : $0 }
                    )
                )
            }
            .sheet(isPresented: $showTitlePicker) {
                TitleFilterSheet(text: $filters.titleContains)
            }
        }
    }
}

// MARK: - Checklist picker sheet

struct ChecklistPickerSheet: View {
    let title: String
    let options: [(String, Int)]
    @Binding var selected: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [(String, Int)] {
        search.isEmpty ? options : options.filter { $0.0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.0) { value, count in
                HStack {
                    Text(value)
                    Spacer()
                    Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: selected.contains(value) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(selected.contains(value) ? Color.accentColor : .secondary)
                        .font(.title3)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected.contains(value) { selected.remove(value) }
                    else { selected.insert(value) }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $search).autocorrectionDisabled()
                }
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Title contains text sheet

struct TitleFilterSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Words in the title", text: $text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit { dismiss() }
                }
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
                .padding(.horizontal, 20)
                .padding(.top, 24)
                Spacer()
            }
            .navigationTitle("Title Contains")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { text = ""; dismiss() }
                        .foregroundStyle(.red).disabled(text.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(180), .medium])
    }
}

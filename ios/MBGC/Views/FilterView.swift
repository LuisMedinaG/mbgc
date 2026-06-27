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

struct GameFilters: Equatable {
    var specs: [FilterField: FilterSpec] = [:]

    var isEmpty: Bool { specs.isEmpty }
    var activeCount: Int { specs.count }

    func apply(_ games: [Game]) -> [Game] {
        guard !isEmpty else { return games }
        return games.filter { passes($0) }
    }

    private func passes(_ game: Game) -> Bool {
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
        case .yearPublished:
            guard let v = game.yearPublished else { return true }
            return check(Double(v))
        }
    }
}

// MARK: - FilterView

struct FilterView: View {
    @Binding var filters: GameFilters
    @Environment(\.dismiss) private var dismiss
    @State private var exactInputs: [FilterField: String] = [:]

    private var enabledFields: [FilterField] { FilterField.allCases.filter { filters.specs[$0] != nil } }
    private var otherFields: [FilterField] { FilterField.allCases.filter { filters.specs[$0] == nil } }

    var body: some View {
        NavigationStack {
            List {
                if !enabledFields.isEmpty {
                    Section("Enabled filters") {
                        ForEach(enabledFields) { field in
                            filterRow(field)
                        }
                    }
                }
                Section(enabledFields.isEmpty ? "Select filters" : "Other filters") {
                    ForEach(otherFields) { field in
                        filterRow(field)
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear All") { filters.specs.removeAll() }
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

    @ViewBuilder
    private func filterRow(_ field: FilterField) -> some View {
        let spec = filters.specs[field]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: field.icon)
                    .frame(width: 24)
                    .foregroundStyle(field.color)
                Text(field.rawValue)
                    .font(.body)
                Spacer()
                modeMenu(field, spec: spec)
            }

            if let spec {
                if spec.mode == .exactly {
                    exactlyInput(field)
                } else {
                    sliderControl(field, spec: spec)
                }
            }
        }
        .padding(.vertical, spec != nil ? 4 : 0)
        .animation(.easeInOut(duration: 0.2), value: spec != nil)
    }

    private func modeMenu(_ field: FilterField, spec: FilterSpec?) -> some View {
        Menu {
            Button("Off") {
                filters.specs[field] = nil
                exactInputs[field] = nil
            }
            ForEach(FilterMode.allCases) { mode in
                Button(mode.rawValue) {
                    let v = filters.specs[field]?.value ?? field.defaultValue
                    filters.specs[field] = FilterSpec(mode: mode, value: v)
                    if mode == .exactly {
                        exactInputs[field] = field.formatValue(v)
                    } else {
                        exactInputs[field] = nil
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(spec?.mode.rawValue ?? "Off")
                    .foregroundStyle(spec?.mode.color ?? .secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                value: Binding(
                    get: { spec.value },
                    set: { filters.specs[field]?.value = $0 }
                ),
                in: field.range,
                step: field.step
            )
            .tint(spec.mode.color)

            HStack {
                Spacer()
                Text(field.formatValue(spec.value) + (field.unit.map { " \($0)" } ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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

            if let unit = field.unit {
                Text(unit)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

import SwiftUI

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

    // BGG-familiar order: classification → players/time → ratings → credits/dates.
    // Single unified list so set filters, numeric filters, title, and language can be
    // interleaved instead of always rendering as separate blocks.
    private static let rowOrder: [FilterRowKind] = [
        .set(.types), .set(.categories), .set(.mechanics),
        .numeric(.players), .numeric(.playtime),
        .numeric(.weight), .numeric(.bestFor),
        .numeric(.rating), .numeric(.bggRank), .numeric(.userRating),
        .language,
        .set(.designers), .set(.artists), .set(.publishers),
        .numeric(.yearPublished), .numeric(.timesPlayed),
        .title,
    ]

    private func isActive(_ row: FilterRowKind) -> Bool {
        switch row {
        case .title:          return !filters.titleContains.isEmpty
        case .language:       return !filters.languageLevels.isEmpty
        case .set(let field): return filters.setFilters[field] != nil
        case .numeric(let field): return filters.specs[field] != nil
        }
    }

    var body: some View {
        Group {
            if !filters.isEmpty {
                Section("Enabled filters") {
                    ForEach(Self.rowOrder.filter(isActive)) { rowView($0) }
                }
            }
            Section(filters.isEmpty ? "Select filters" : "Other filters") {
                ForEach(Self.rowOrder.filter { !isActive($0) }) { rowView($0) }
            }
        }
        .onChange(of: filters.isEmpty) { _, isEmpty in
            if isEmpty { exactInputs.removeAll(); languageExpanded = false }
        }
    }

    @ViewBuilder
    private func rowView(_ row: FilterRowKind) -> some View {
        switch row {
        case .title:              titleRow
        case .language:           languageDependenceRow
        case .set(let field):     checklistRow(field)
        case .numeric(let field): filterRow(field)
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
                fieldIcon(field).frame(width: 24).foregroundStyle(field.color)
                Text(field.rawValue).font(.body)
                Spacer()
                modeMenu(field, spec: spec)
            }
            if let spec {
                switch spec.mode {
                case .exactly:
                    exactlyInput(field)
                case .between:
                    betweenControl(field, spec: spec)
                case .minimum, .maximum:
                    sliderControl(field, spec: spec)
                }
            }
        }
        .padding(.vertical, spec != nil ? 4 : 0)
        .animation(.easeInOut(duration: 0.2), value: spec != nil)
    }

    @ViewBuilder
    private func fieldIcon(_ field: FilterField) -> some View {
        if field.isCustomImage { Image(field.icon) } else { Image(systemName: field.icon) }
    }

    private func modeMenu(_ field: FilterField, spec: FilterSpec?) -> some View {
        Menu {
            Button("Off") { filters.specs[field] = nil; exactInputs[field] = nil }
            Divider()
            modeButton(.minimum, field: field)
            modeButton(.maximum, field: field)
            modeButton(.exactly, field: field)
            if field.supportsBetween {
                Divider()
                modeButton(.between, field: field)
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

    private func modeButton(_ mode: FilterMode, field: FilterField) -> some View {
        Button(mode.rawValue) {
            let v = filters.specs[field]?.value ?? field.defaultValue
            let upper = filters.specs[field]?.upperValue ?? defaultUpperValue(for: field, lower: v)
            filters.specs[field] = FilterSpec(mode: mode, value: v, upperValue: mode == .between ? upper : nil)
            exactInputs[field] = mode == .exactly ? field.formatValue(v) : nil
        }
    }

    private func defaultUpperValue(for field: FilterField, lower: Double) -> Double {
        min(field.range.upperBound, max(lower + field.step, field.defaultValue + field.step))
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

    private func betweenControl(_ field: FilterField, spec: FilterSpec) -> some View {
        let upper = spec.upperValue ?? defaultUpperValue(for: field, lower: spec.value)
        let lowerValue = min(spec.value, upper)
        let upperValue = max(spec.value, upper)

        return VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { lowerValue },
                    set: { newValue in
                        filters.specs[field]?.value = min(newValue, filters.specs[field]?.upperValue ?? upperValue)
                    }
                ),
                in: field.range,
                step: field.step
            )
            .tint(spec.mode.color)

            Slider(
                value: Binding(
                    get: { upperValue },
                    set: { newValue in
                        filters.specs[field]?.upperValue = max(newValue, filters.specs[field]?.value ?? lowerValue)
                    }
                ),
                in: field.range,
                step: field.step
            )
            .tint(spec.mode.color)

            HStack {
                Spacer()
                Text("\(field.formatValue(lowerValue)) – \(field.formatValue(upperValue))" + (field.unit.map { " \($0)" } ?? ""))
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

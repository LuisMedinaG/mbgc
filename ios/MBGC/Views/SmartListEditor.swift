import SwiftData
import SwiftUI

/// A specialized editor for defining `SmartRule` logic.
/// It allows users to combine, intersect, subtract, or exclude games from other
/// collections and apply attribute-based filters.
struct SmartListEditor: View {
    @State private var rule: SmartRule
    let lists: [Collection]
    let allGames: [Game]
    let onSave: (SmartRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var activeBucket: Bucket?
    @State private var showBaseSelect = false
    @State private var baseSelected: Bool
    @State private var showTitlePicker = false
    @State private var activeChecklist: SetFilterField?

    private var baseCollections: [Collection] { lists.filter { rule.base.contains($0.id) } }

    private func gameCount(_ list: Collection) -> Int {
        list.isSmart ? list.smartGames(collections: lists, allGames: allGames).count : list.games.count
    }

    /// Games from the base lists + set operations, before this rule's own filters — empty until a list is chosen.
    private var resolvedGames: [Game] {
        guard baseSelected else { return [] }
        func ids(_ uuids: [UUID]) -> [Set<Int>] {
            uuids.compactMap { id in lists.first { $0.id == id } }.map { Set(gameList($0).map(\.bggId)) }
        }
        var members: Set<Int> = []
        for set in ids(rule.base) { members.formUnion(set) }
        for set in ids(rule.combine) { members.formUnion(set) }
        for set in ids(rule.intersect) { members.formIntersection(set) }
        for set in ids(rule.subtract) { members.subtract(set) }
        for set in ids(rule.exclude) { members.formSymmetricDifference(set) }
        return allGames.filter { members.contains($0.bggId) }
    }

    private func gameList(_ list: Collection) -> [Game] {
        list.isSmart ? list.smartGames(collections: lists, allGames: allGames) : list.games
    }

    init(rule: SmartRule, lists: [Collection], allGames: [Game], onSave: @escaping (SmartRule) -> Void) {
        _rule = State(initialValue: rule)
        self.lists = lists
        self.allGames = allGames
        self.onSave = onSave
        _baseSelected = State(initialValue: !rule.base.isEmpty || !rule.combine.isEmpty || !rule.intersect.isEmpty || !rule.subtract.isEmpty || !rule.exclude.isEmpty)
    }

    enum Bucket: String, CaseIterable, Identifiable {
        case combine = "Combine", intersect = "Intersect", subtract = "Subtract", exclude = "Exclude"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .combine:   return "plus.square.on.square"
            case .intersect: return "square.on.square.intersection.dashed"
            case .subtract:  return "minus.square"
            case .exclude:   return "xmark.square"
            }
        }
    }

    private func ids(_ b: Bucket) -> [UUID] {
        switch b {
        case .combine:   return rule.combine
        case .intersect: return rule.intersect
        case .subtract:  return rule.subtract
        case .exclude:   return rule.exclude
        }
    }
    private func setIds(_ v: [UUID], _ b: Bucket) {
        switch b {
        case .combine:   rule.combine = v
        case .intersect: rule.intersect = v
        case .subtract:  rule.subtract = v
        case .exclude:   rule.exclude = v
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Lists") {
                    baseRow
                    if baseSelected {
                        fromSelectedGroup
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        ForEach(Bucket.allCases) { bucket in
                            operationRow(bucket)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                FilterRows(filters: $rule.filters, games: resolvedGames, showTitlePicker: $showTitlePicker, activeChecklist: $activeChecklist)
            }
            .navigationTitle("Smart Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(rule); dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(item: $activeBucket) { bucket in
                ListPickerSheet(
                    title: bucket.rawValue,
                    lists: lists.filter { !rule.base.contains($0.id) },
                    selected: Binding(
                        get: { Set(ids(bucket)) },
                        set: { setIds(Array($0), bucket) }
                    )
                )
            }
            .sheet(isPresented: $showBaseSelect) {
                ListPickerSheet(
                    title: "Select Lists",
                    lists: lists,
                    selected: Binding(
                        get: { Set(rule.base) },
                        set: { rule.base = Array($0) }
                    )
                )
            }
            .sheet(item: $activeChecklist) { field in
                ChecklistPickerSheet(
                    title: field.rawValue,
                    options: field.values(from: resolvedGames),
                    selected: Binding(
                        get: { rule.filters.setFilters[field] ?? [] },
                        set: { rule.filters.setFilters[field] = $0.isEmpty ? nil : $0 }
                    )
                )
            }
            .sheet(isPresented: $showTitlePicker) {
                TitleFilterSheet(text: $rule.filters.titleContains)
            }
        }
    }

    private var baseRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle").frame(width: 24).foregroundStyle(Color.red)
            Text("Lists").font(.body).foregroundStyle(.primary)
            Spacer()
            baseMenu
        }
    }

    private var baseMenu: some View {
        Menu {
            Button {
                baseSelected = false
                rule.base = []
                rule.combine = []; rule.intersect = []; rule.subtract = []; rule.exclude = []
            } label: {
                if baseSelected { Text("Off") } else { Label("Off", systemImage: "checkmark") }
            }
            Button {
                baseSelected = true                       // reveal ops panel inline; no sheet
            } label: {
                if baseSelected { Label("Choose…", systemImage: "checkmark") } else { Text("Choose…") }
            }
        } label: {
            HStack(spacing: 3) {
                Text(baseSelected ? "Choose…" : "Off")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.vertical, 4)
            .padding(.leading, 8)
            .contentShape(Rectangle())
        }
        .tint(.primary)
    }

    private var fromSelectedRow: some View {
        HStack(spacing: 12) {
            Text("From selected").font(.body).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { showBaseSelect = true }
    }

    private func selectedBaseRow(_ list: Collection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: list.isDefault ? "square.grid.2x2.fill" : list.effectiveIconName)
                .foregroundStyle(Color(hex: list.effectiveColorHex) ?? .orange).frame(width: 24)
            Text(list.name)
            Spacer()
            Text("\(gameCount(list))").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    // "From selected" + the chosen base lists, grouped in one tinted box.
    private var fromSelectedGroup: some View {
        VStack(spacing: 0) {
            fromSelectedRow
                .padding(.horizontal, 14).padding(.vertical, 12)
            ForEach(baseCollections) { list in
                Divider().padding(.leading, 14)
                selectedBaseRow(list)
                    .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // One set operation, indented under the base with a ↳ and its own tinted capsule.
    private func operationRow(_ bucket: Bucket) -> some View {
        let count = ids(bucket).count
        return HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .font(.subheadline).foregroundStyle(.secondary).frame(width: 18)
            Button { activeBucket = bucket } label: {
                HStack(spacing: 12) {
                    Image(systemName: bucket.icon).frame(width: 24).foregroundStyle(.primary)
                    Text(bucket.rawValue).font(.body).foregroundStyle(.primary)
                    Spacer()
                    if count > 0 {
                        Text("\(count)").foregroundStyle(Color.accentColor).font(.subheadline.weight(.medium))
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Multi-select picker over existing lists, binding a Set of Collection.id.
struct ListPickerSheet: View {
    let title: String
    let lists: [Collection]
    @Binding var selected: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(lists) { list in
                HStack(spacing: 12) {
                    Image(systemName: list.isDefault ? "square.grid.2x2.fill" : list.effectiveIconName)
                        .foregroundStyle(Color(hex: list.effectiveColorHex) ?? .orange)
                        .frame(width: 24)
                    Text(list.name)
                    Spacer()
                    Image(systemName: selected.contains(list.id) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(selected.contains(list.id) ? Color.accentColor : .secondary)
                        .font(.title3)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected.contains(list.id) { selected.remove(list.id) }
                    else { selected.insert(list.id) }
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { selected.removeAll() }
                        .foregroundStyle(.red).disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

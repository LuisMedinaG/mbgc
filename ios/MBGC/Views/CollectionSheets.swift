import SwiftData
import SwiftUI

/// Create-flow sheet. Owns its own `@Environment(\.modelContext)` so SwiftData
/// writes are guaranteed to land on the active context (sheets can't reliably
/// inherit context through computed view properties).
struct CreateCollectionSheet: View {
    let kind: CollectionKind
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @Query private var allGames: [Game]
    @State private var name = ""
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var rule = SmartRule()
    @State private var showRuleEditor = false
    @State private var errorMessage: String?
    private var orderedCollections: [Collection] { Collection.ordered(collections) }

    init(kind: CollectionKind) {
        self.kind = kind
        // Defaults track the first swatch / icon in CollectionPickerBody so
        // they stay in sync if either list changes.
        _selectedColor = State(initialValue: CollectionPickerBody<EmptyView>.colors.first ?? "#3D4A52")
        _selectedIcon = State(initialValue: CollectionPickerBody<EmptyView>.icons.first ?? "list.bullet")
    }

    var body: some View {
        NavigationStack {
            CollectionPickerBody(name: $name, selectedColor: $selectedColor, selectedIcon: $selectedIcon) {
                if kind == .smart { setFiltersPill }
            }
                .navigationTitle(CollectionName.trimmed(name).isEmpty ? "New Collection" : CollectionName.trimmed(name))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { save() }
                            .disabled(CollectionName.trimmed(name).isEmpty)
                    }
                }
                .errorAlert($errorMessage)
                .sheet(isPresented: $showRuleEditor) {
                    SmartListEditor(rule: rule, lists: orderedCollections, allGames: allGames) { rule = $0 }
                }
        }
        .presentationDetents([.large])
    }

    private var setFiltersPill: some View {
        Button { showRuleEditor = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                Text("Set Filters").fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                Text("\(rule.activeCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(Color.white, in: Circle())
            }
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 22)
            .background(Color.green, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func save() {
        let col = Collection(name: CollectionName.prepareForSave(name), desc: "")
        col.colorHex = selectedColor
        col.iconName = selectedIcon
        switch kind {
        case .standard: break
        case .ranked:   col.isRanked = true
        case .smart:    col.isSmart = true; col.setRule(rule)
        }
        modelContext.insert(col)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Couldn't save collection."
        }
    }
}

/// Edit-flow sheet. Reuses CollectionPickerBody so the create / edit
/// surface stays identical. Never saves against Library.
struct RenameCollectionSheet: View {
    let collection: Collection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var errorMessage: String?

    init(collection: Collection, initialName: String) {
        self.collection = collection
        _name = State(initialValue: initialName)
        _selectedColor = State(initialValue: collection.effectiveColorHex)
        _selectedIcon = State(initialValue: collection.effectiveIconName)
    }

    var body: some View {
        NavigationStack {
            CollectionPickerBody(name: $name, selectedColor: $selectedColor, selectedIcon: $selectedIcon)
                .navigationTitle(CollectionName.trimmed(name).isEmpty ? "Edit Collection" : CollectionName.trimmed(name))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(CollectionName.trimmed(name).isEmpty)
                    }
                }
                .errorAlert($errorMessage)
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard !collection.isDefault else { return }
        collection.name = CollectionName.prepareForSave(name)
        collection.colorHex = selectedColor
        collection.iconName = selectedIcon
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Couldn't save collection."
        }
    }
}

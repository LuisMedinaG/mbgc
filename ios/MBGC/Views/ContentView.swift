import SwiftUI

enum HomeTab { case discover, collection }

struct ContentView: View {
    @State private var vibesViewModel = VibesViewModel()
    @State private var tab: HomeTab = .collection
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showCreate = false
    @State private var createName = ""
    @State private var createDescription = ""

    var body: some View {
        Group {
            switch tab {
            case .collection: VibesView(viewModel: vibesViewModel)
            case .discover:   LibraryView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .bottom) {
                HomePillView(tab: $tab)
                Spacer()
                VStack(spacing: 10) {
                    Button {
                        tab = .collection
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .sheet(isPresented: $showSearch)   { SearchView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showCreate)   { createSheet }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $createName)
                TextField("Description (optional)", text: $createDescription)
            }
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showCreate = false
                        createName = ""
                        createDescription = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = createName
                        let desc = createDescription
                        showCreate = false
                        createName = ""
                        createDescription = ""
                        Task { await vibesViewModel.create(name: name, description: desc) }
                    }
                    .disabled(createName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct HomePillView: View {
    @Binding var tab: HomeTab

    var body: some View {
        HStack(spacing: 0) {
            pillButton("Discover", for: .discover)
            pillButton("Collection", for: .collection)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private func pillButton(_ label: String, for target: HomeTab) -> some View {
        Button { tab = target } label: {
            Text(label)
                .font(.subheadline.weight(tab == target ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundStyle(tab == target ? Color(.systemBackground) : .secondary)
                .background(tab == target ? Color(.label) : Color.clear)
                .clipShape(Capsule())
        }
    }
}

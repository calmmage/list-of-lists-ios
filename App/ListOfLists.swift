import SwiftUI

@main
struct ListOfListsApp: App {
    @StateObject private var store: Store

    init() {
        var directory: URL?
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--ui-testing") {
            let namespace = process.environment["LIST_TEST_NAMESPACE"].flatMap(UUID.init(uuidString:)) ?? UUID()
            directory = URL.temporaryDirectory.appending(path: namespace.uuidString)
        }
        _store = StateObject(wrappedValue: Store(directory: directory))
    }

    var body: some Scene {
        WindowGroup {
            Pages()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

private enum Page: Hashable {
    case directory
    case list(UUID)
}

private struct Pages: View {
    @EnvironmentObject private var store: Store
    @State private var page = Page.directory

    private var pages: [Screen<Page>] {
        var screens = store.lists.map { Screen(id: Page.list($0.id), title: $0.title) }
        screens.insert(Screen(id: .directory, title: "List of Lists"), at: screens.count / 2)
        return screens
    }

    var body: some View {
        Screens(pages: pages, home: .directory, current: $page) { id in
            NavigationStack {
                Group {
                    switch id {
                    case .directory:
                        Directory { listID in withAnimation { page = .list(listID) } }
                    case let .list(listID):
                        if let list = store.lists.first(where: { $0.id == listID }) {
                            Items(list: list)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        Button("All lists") { withAnimation { page = .directory } }
                                    }
                                }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { ScreenMenuButton() } }
            }
            .accessibilityHidden(id != page)
        }
        .alert("Storage error", isPresented: Binding(
            get: { store.error != nil }, set: { if !$0 { store.error = nil } }
        )) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}

private struct Directory: View {
    let open: (UUID) -> Void
    @EnvironmentObject private var store: Store
    @State private var adding = false
    @State private var removal: NamedList?
    @State private var title = ""

    var body: some View {
        List {
            ForEach(store.lists) { list in
                Button { open(list.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(list.title)
                            Text(list.items.count == 1 ? "1 item" : "\(list.items.count) items")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("list-\(list.title)")
                .contextMenu { Button("Delete list", role: .destructive) { removal = list } }
                .swipeActions(allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) { removal = list }
                }
            }
        }
        .overlay {
            if store.lists.isEmpty {
                ContentUnavailableView("No lists yet", systemImage: "list.bullet.indent",
                                       description: Text("Add a list to start collecting items."))
            }
        }
        .navigationTitle("List of Lists")
        .safeAreaInset(edge: .bottom) {
            BottomButton(title: "Add list") { title = ""; adding = true }
        }
        .alert("New list", isPresented: $adding) {
            TextField("Title", text: $title)
            Button("Cancel", role: .cancel) {}
            Button("Add") { _ = store.addList(title) }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("Delete “\(removal?.title ?? "")” and all its items?",
                            isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
                            titleVisibility: .visible, presenting: removal) { list in
            Button("Delete list", role: .destructive) { _ = store.deleteList(list.id) }
        }
    }
}

private struct Items: View {
    let list: NamedList
    @EnvironmentObject private var store: Store
    @State private var adding = false
    @State private var editing: ListItem?
    @State private var removal: ListItem?
    @State private var title = ""

    var body: some View {
        List {
            ForEach(list.items) { item in
                Button {
                    title = item.title
                    editing = item
                } label: {
                    Text(item.title).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Delete item", role: .destructive) { removal = item } }
                .swipeActions(allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) { removal = item }
                }
            }
        }
        .overlay {
            if list.items.isEmpty {
                ContentUnavailableView("No items yet", systemImage: "list.bullet")
            }
        }
        .navigationTitle(list.title)
        .safeAreaInset(edge: .bottom) {
            BottomButton(title: "Add item") { title = ""; adding = true }
        }
        .alert("New item", isPresented: $adding) {
            TextField("Title", text: $title)
            Button("Cancel", role: .cancel) {}
            Button("Add") { _ = store.addItem(title, to: list.id) }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Rename item", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }),
               presenting: editing) { item in
            TextField("Title", text: $title)
            Button("Cancel", role: .cancel) {}
            Button("Save") { _ = store.renameItem(item.id, in: list.id, to: title) }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("Delete “\(removal?.title ?? "")”?",
                            isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
                            titleVisibility: .visible, presenting: removal) { item in
            Button("Delete item", role: .destructive) { _ = store.deleteItem(item.id, from: list.id) }
        }
    }
}

private struct BottomButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

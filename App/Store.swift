import Combine
import Foundation

struct ListItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
}

struct NamedList: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var items: [ListItem] = []
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var lists: [NamedList] = []
    @Published var error: String?

    private let file: URL
    private var loadError: String?

    init(directory: URL? = nil) {
        let home = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListOfLists", isDirectory: true)
        file = home.appendingPathComponent("lists.json")
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let data = try Data(contentsOf: file)
            lists = try JSONDecoder().decode([NamedList].self, from: data)
        } catch let failure as CocoaError where failure.code == .fileReadNoSuchFile {
            // A first launch starts with an empty collection.
        } catch {
            let message = "Couldn’t open your lists. " + error.localizedDescription
            loadError = message
            self.error = message
        }
    }

    @discardableResult
    func addList(_ title: String) -> Bool {
        guard let title = validTitle(title) else { return false }
        var updated = lists
        updated.append(NamedList(title: title))
        return save(updated)
    }

    @discardableResult
    func addItem(_ title: String, to listID: UUID) -> Bool {
        guard let title = validTitle(title), let list = index(of: listID) else { return false }
        var updated = lists
        updated[list].items.append(ListItem(title: title))
        return save(updated)
    }

    @discardableResult
    func deleteList(_ id: UUID) -> Bool {
        guard let list = index(of: id) else { return false }
        var updated = lists
        updated.remove(at: list)
        return save(updated)
    }

    @discardableResult
    func deleteItem(_ id: UUID, from listID: UUID) -> Bool {
        guard let list = index(of: listID), let item = index(of: id, in: list) else { return false }
        var updated = lists
        updated[list].items.remove(at: item)
        return save(updated)
    }

    @discardableResult
    func renameItem(_ id: UUID, in listID: UUID, to title: String) -> Bool {
        guard let title = validTitle(title), let list = index(of: listID),
              let item = index(of: id, in: list) else { return false }
        var updated = lists
        updated[list].items[item].title = title
        return save(updated)
    }

    private func validTitle(_ raw: String) -> String? {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            error = "Enter a title."
            return nil
        }
        return title
    }

    private func index(of listID: UUID) -> Int? {
        let index = lists.firstIndex { $0.id == listID }
        if index == nil { error = loadError ?? "This list could not be found." }
        return index
    }

    private func index(of itemID: UUID, in list: Int) -> Int? {
        let index = lists[list].items.firstIndex { $0.id == itemID }
        if index == nil { error = "This item could not be found." }
        return index
    }

    private func save(_ updated: [NamedList]) -> Bool {
        if let loadError {
            error = loadError
            return false
        }
        do {
            try JSONEncoder().encode(updated).write(to: file, options: .atomic)
            lists = updated
            error = nil
            return true
        } catch {
            self.error = "Couldn’t save your lists. " + error.localizedDescription
            return false
        }
    }
}

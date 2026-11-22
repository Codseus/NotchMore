import Combine
import Foundation

struct TodoItem: Codable, Identifiable {
    let id: UUID
    let title: String
    var isCompleted: Bool
}

@MainActor
final class TodoListStore: ObservableObject {
    @Published private(set) var items: [TodoItem]
    private let defaults: UserDefaults
    private static let storageKey = "notchTodoItems"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.storageKey) ?? Data()
        items = (try? JSONDecoder().decode([TodoItem].self, from: data)) ?? []
    }

    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        save(items + [TodoItem(id: UUID(), title: title, isCompleted: false)])
    }

    func toggleCompletion(for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var updatedItems = items
        updatedItems[index].isCompleted.toggle()
        save(updatedItems)
    }

    func remove(_ id: UUID) {
        save(items.filter { $0.id != id })
    }

    private func save(_ updatedItems: [TodoItem]) {
        guard let data = try? JSONEncoder().encode(updatedItems) else { return }
        defaults.set(data, forKey: Self.storageKey)
        items = updatedItems
    }
}

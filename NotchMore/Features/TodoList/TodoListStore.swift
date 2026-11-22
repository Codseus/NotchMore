import Combine
import Foundation

struct TodoItem: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    var isCompleted: Bool
    var removeAfter: Date?
}

@MainActor
final class TodoListStore: ObservableObject {
    @Published private(set) var items: [TodoItem]
    private let defaults: UserDefaults
    private var removalTask: Task<Void, Never>?
    private static let storageKey = "notchTodoItems"
    private static let completionGracePeriod: TimeInterval = 5

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.storageKey) ?? Data()
        items = (try? JSONDecoder().decode([TodoItem].self, from: data)) ?? []

        let now = Date()
        let unexpired = items.filter { $0.removeAfter.map { $0 > now } ?? true }
        // Older builds saved a completion flag without a removal date.
        let legacyRemovalDate = now.addingTimeInterval(Self.completionGracePeriod)
        let restored = unexpired.map { item in
            var item = item
            if item.isCompleted && item.removeAfter == nil {
                item.removeAfter = legacyRemovalDate
            }
            return item
        }
        if restored != items {
            save(restored)
        } else {
            scheduleRemoval()
        }
    }

    deinit {
        removalTask?.cancel()
    }

    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        save(items + [TodoItem(id: UUID(), title: title, isCompleted: false)])
    }

    func setCompleted(_ isCompleted: Bool, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
            items[index].isCompleted != isCompleted
        else { return }

        var updatedItems = items
        updatedItems[index].isCompleted = isCompleted
        updatedItems[index].removeAfter =
            isCompleted ? Date().addingTimeInterval(Self.completionGracePeriod) : nil
        save(updatedItems)
    }

    func remove(_ id: UUID) {
        save(items.filter { $0.id != id })
    }

    private func save(_ updatedItems: [TodoItem]) {
        guard let data = try? JSONEncoder().encode(updatedItems) else { return }
        defaults.set(data, forKey: Self.storageKey)
        items = updatedItems
        scheduleRemoval()
    }

    private func scheduleRemoval() {
        removalTask?.cancel()
        guard let nextRemoval = items.compactMap(\.removeAfter).min() else {
            removalTask = nil
            return
        }

        removalTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, nextRemoval.timeIntervalSinceNow)))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.removeExpiredItems()
        }
    }

    private func removeExpiredItems() {
        let now = Date()
        let remaining = items.filter { $0.removeAfter.map { $0 > now } ?? true }
        if remaining.count == items.count {
            scheduleRemoval()
        } else {
            save(remaining)
        }
    }
}

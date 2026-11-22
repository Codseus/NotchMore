import SwiftUI

struct TodoListView: View {
    let panelWidth: CGFloat
    let panelHeight: CGFloat

    @StateObject private var store = TodoListStore()
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("To-Do List", systemImage: "checklist")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 6) {
                TextField("New task", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(addTask)
                Button(action: addTask) {
                    Image(systemName: "plus")
                }
                .buttonStyle(NotchIconButtonStyle(size: 24, cornerRadius: 7))
                .accessibilityLabel("Add task")
                .help("Add task")
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if store.items.isEmpty {
                Text("No tasks yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.items) { item in
                            taskRow(item)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
    }

    private func taskRow(_ item: TodoItem) -> some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { item.isCompleted },
                set: { _ in store.toggleCompletion(for: item.id) }
            )) {
                Text(item.title)
                    .font(.system(size: 12))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(item.title)

            Button {
                store.remove(item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(NotchIconButtonStyle(size: 22, cornerRadius: 6))
            .accessibilityLabel("Delete task")
            .help("Delete task")
        }
    }

    private func addTask() {
        store.add(draft)
        draft = ""
    }
}

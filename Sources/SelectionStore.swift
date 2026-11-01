import SwiftUI
import Combine

@MainActor
final class SelectionStore: ObservableObject {
    @Published var isSelecting = false
    @Published var selected: Set<String> = []
    @Published var markedForDeletion: Set<String> = []

    func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    func selectAll(_ ids: [String]) {
        selected = Set(ids)
    }

    func clearSelection() {
        selected.removeAll()
        isSelecting = false
    }

    func markSelectedForDeletion() {
        markedForDeletion.formUnion(selected)
        selected.removeAll()
        isSelecting = false
    }

    func toggleMarked(_ id: String) {
        if markedForDeletion.contains(id) {
            markedForDeletion.remove(id)
        } else {
            markedForDeletion.insert(id)
        }
    }
}

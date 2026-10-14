import SwiftUI
import TrafficControlCore

/// Rows that reorder by dragging vertically: the grabbed row follows the pointer (up and down only,
/// within the list) while the others slide aside, and the new order is saved on release.
/// One view rather than a row per entry, because grouped forms ignore `onMove`.
struct ReorderableChoiceList<Row: View>: View {
    let choices: [BrowserChoice]
    @ViewBuilder let row: (BrowserChoice) -> Row
    let onReorder: ([BrowserChoice]) -> Void

    private let rowHeight: CGFloat = 52
    @State private var dragged: String?
    @State private var translation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slide: Animation? { reduceMotion ? nil : .easeOut(duration: 0.15) }

    var body: some View {
        let order = displayOrder
        VStack(spacing: 0) {
            ForEach(Array(order.enumerated()), id: \.element.id) { index, choice in
                let isDragged = choice.id == dragged
                row(choice)
                    .padding(.horizontal, 10)
                    .frame(height: rowHeight)
                    .background {
                        if isDragged {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.background)
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        }
                    }
                    .overlay(alignment: .top) {
                        if index > 0 && !isDragged && order[index - 1].id != dragged {
                            Divider().padding(.leading, 64)
                        }
                    }
                    .opacity(isDragged ? 0.85 : 1)
                    .offset(y: isDragged ? draggedOffset(at: index) : 0)
                    .zIndex(isDragged ? 1 : 0)
                    // The grabbed row tracks the pointer exactly; only the rows making room animate.
                    .transaction { if isDragged { $0.animation = nil } }
                    .contentShape(Rectangle())
                    .gesture(drag(choice))
            }
        }
        .animation(slide, value: order.map(\.id))
        .coordinateSpace(.named(Self.space))
    }

    /// Measured against the list, not the row: the row moves with the pointer, so its own
    /// coordinates would only report half the movement.
    private static var space: String { "ReorderableChoiceList" }

    private func drag(_ choice: BrowserChoice) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragged == nil { dragged = choice.id }
                translation = value.translation.height
            }
            .onEnded { _ in
                let order = displayOrder
                withAnimation(slide) {
                    dragged = nil
                    translation = 0
                    if order.map(\.id) != choices.map(\.id) { onReorder(order) }
                }
            }
    }

    private var startIndex: Int? { choices.firstIndex { $0.id == dragged } }

    /// The pointer's movement, kept inside the list.
    private var clampedTranslation: CGFloat {
        guard let start = startIndex else { return 0 }
        let up = -CGFloat(start) * rowHeight
        let down = CGFloat(choices.count - 1 - start) * rowHeight
        return min(max(translation, up), down)
    }

    /// `choices` with the dragged row moved to the slot under the pointer.
    private var displayOrder: [BrowserChoice] {
        guard let start = startIndex else { return choices }
        let target = start + Int((clampedTranslation / rowHeight).rounded())
        var order = choices
        order.insert(order.remove(at: start), at: target)
        return order
    }

    /// Keeps the dragged row under the pointer even though its slot has moved.
    private func draggedOffset(at index: Int) -> CGFloat {
        guard let start = startIndex else { return 0 }
        return clampedTranslation - CGFloat(index - start) * rowHeight
    }
}

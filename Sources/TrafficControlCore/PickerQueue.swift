import Foundation

/// FIFO requests stay queued until their own identifier is resolved.
public struct PickerQueue<Element: Identifiable> where Element.ID: Equatable {
    private var elements: [Element] = []

    public init() {}

    public var head: Element? { elements.first }
    public var isEmpty: Bool { elements.isEmpty }
    public var count: Int { elements.count }

    public mutating func append(_ element: Element) { elements.append(element) }

    @discardableResult
    public mutating func resolve(id: Element.ID) -> Bool {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return false }
        elements.remove(at: index)
        return true
    }

    public static func needsRecovery(choices: [some Any]) -> Bool { choices.isEmpty }
}

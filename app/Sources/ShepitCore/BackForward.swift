/// The steps back and forward through the places the window has shown (back and forward design §4–5). A step that is
/// gone (a removed meeting, a merged person) is skipped by the `alive` test and dropped on the way, as is a step equal
/// to the current one, which a gone step between them can leave next to it.
public struct BackForward<Step: Equatable> {
    /// Steps kept behind the current one; the oldest goes (design §2).
    public static var limit: Int { 50 }

    public private(set) var current: Step?
    /// Nearest last on both sides.
    private var behind: [Step] = []
    private var ahead: [Step] = []

    public init() {}

    /// A new step, unless it is the current one: applying a step back gives that step again, and it records nothing.
    public mutating func visit(_ step: Step) {
        guard step != current else { return }
        if let current { behind.append(current) }
        if behind.count > Self.limit { behind.removeFirst() }
        ahead = []
        current = step
    }

    /// The step moved to, or nil when no step behind is alive.
    public mutating func back(alive: (Step) -> Bool) -> Step? {
        Self.move(from: &behind, to: &ahead, current: &current, alive)
    }

    public mutating func forward(alive: (Step) -> Bool) -> Step? {
        Self.move(from: &ahead, to: &behind, current: &current, alive)
    }

    /// Where `back` would go, for the hint and the greyed arrow.
    public func peekBack(alive: (Step) -> Bool) -> Step? { behind.last { $0 != current && alive($0) } }

    public func peekForward(alive: (Step) -> Bool) -> Step? { ahead.last { $0 != current && alive($0) } }

    /// Every step equal to `old` becomes `new`, or goes with nil: the running transcript once it is a meeting, or once
    /// it ended without becoming one.
    public mutating func replace(_ old: Step, with new: Step?) {
        let swap = { $0 == old ? new : $0 }
        behind = behind.compactMap(swap)
        ahead = ahead.compactMap(swap)
        current = current.flatMap(swap)
    }

    private static func move(from: inout [Step], to: inout [Step], current: inout Step?, _ alive: (Step) -> Bool) -> Step? {
        while let step = from.popLast() {
            guard step != current, alive(step) else { continue }
            if let current { to.append(current) }
            current = step
            return step
        }
        return nil
    }
}

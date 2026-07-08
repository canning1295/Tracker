import Foundation

enum CrownMenuScrollAction: Equatable {
    case select(Int)
    case back
    case forward(Int)
}

struct CrownMenuScrollModel: Equatable {
    var optionCount: Int
    var hasBack: Bool
    var hasForward: Bool

    var crownLowerBound: Double {
        -Double(maximumLogicalIndex)
    }

    var crownUpperBound: Double {
        -Double(minimumLogicalIndex)
    }

    func clampedSelection(_ selectionIndex: Int) -> Int {
        guard optionCount > 0 else { return 0 }
        return min(max(selectionIndex, 0), optionCount - 1)
    }

    func crownValue(forSelection selectionIndex: Int) -> Double {
        -Double(clampedSelection(selectionIndex))
    }

    func action(forCrownValue crownValue: Double, currentSelectionIndex: Int) -> CrownMenuScrollAction? {
        guard optionCount > 0 else { return nil }

        let logicalIndex = Int((-crownValue).rounded())
        let last = optionCount - 1
        let currentSelection = clampedSelection(currentSelectionIndex)

        if logicalIndex < 0 {
            return currentSelection == 0 ? .back : .select(0)
        }

        if logicalIndex > last {
            return currentSelection == last ? .forward(last) : .select(last)
        }

        let nextSelection = min(max(logicalIndex, 0), last)
        return nextSelection == currentSelection ? nil : .select(nextSelection)
    }

    private var minimumLogicalIndex: Int {
        hasBack ? -1 : 0
    }

    private var maximumLogicalIndex: Int {
        guard optionCount > 0 else { return 0 }
        return optionCount - 1 + (hasForward ? 1 : 0)
    }
}

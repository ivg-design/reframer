import Foundation

struct ScrollStepAccumulator {
    private var accumulator: Double = 0
    private let threshold: Double

    init(threshold: Double = 0.5) {
        self.threshold = threshold
    }

    mutating func steps(for delta: Double, hasPreciseDeltas: Bool) -> [VideoState.FrameStepDirection] {
        guard delta != 0 else { return [] }

        if !hasPreciseDeltas {
            return delta > 0 ? [.backward] : [.forward]
        }

        accumulator += delta
        var steps: [VideoState.FrameStepDirection] = []

        while abs(accumulator) >= threshold {
            if accumulator > 0 {
                steps.append(.backward)
                accumulator -= threshold
            } else {
                steps.append(.forward)
                accumulator += threshold
            }
        }

        return steps
    }
}

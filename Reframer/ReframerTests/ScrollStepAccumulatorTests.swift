import XCTest
@testable import Reframer

final class ScrollStepAccumulatorTests: XCTestCase {
    func testDiscreteScrollProducesImmediateStep() {
        var accumulator = ScrollStepAccumulator()
        XCTAssertEqual(accumulator.steps(for: 1.0, hasPreciseDeltas: false), [.backward])
        XCTAssertEqual(accumulator.steps(for: -1.0, hasPreciseDeltas: false), [.forward])
    }

    func testPreciseScrollAccumulatesToThreshold() {
        var accumulator = ScrollStepAccumulator(threshold: 0.5)
        XCTAssertEqual(accumulator.steps(for: 0.2, hasPreciseDeltas: true), [])
        XCTAssertEqual(accumulator.steps(for: 0.3, hasPreciseDeltas: true), [.backward])
    }

    func testPreciseScrollNegativeAccumulation() {
        var accumulator = ScrollStepAccumulator(threshold: 0.5)
        XCTAssertEqual(accumulator.steps(for: -0.25, hasPreciseDeltas: true), [])
        XCTAssertEqual(accumulator.steps(for: -0.25, hasPreciseDeltas: true), [.forward])
    }
}

import XCTest
@testable import Mantiza

@MainActor final class CalibrationTests: XCTestCase {
    func testFitRecoversLine() throws {
        // Pointer lands at 0.97 * u + 0.012 (a slightly scaled, offset screen).
        let samples = [0.12, 0.5, 0.88].map { f -> CalibrationFit.Sample in
            let u = Int(f * 32767)
            return .init(units: u, landed: 0.97 * Double(u) / 32767 + 0.012)
        }
        let axis = try CalibrationFit.axis(samples).get()
        XCTAssertEqual(axis.a, 0.97, accuracy: 1e-6)
        XCTAssertEqual(axis.b, 0.012, accuracy: 1e-6)
        XCTAssertEqual(axis.landed(units: axis.units(for: 0.3)), 0.3, accuracy: 0.0001)
    }

    func testFitRejectsRelativeLookingSlope() {
        let samples = [0.12, 0.5, 0.88].map { CalibrationFit.Sample(units: Int($0 * 32767), landed: 0.5 * $0) }
        guard case .failure(.slope) = CalibrationFit.axis(samples) else { return XCTFail("expected slope failure") }
    }

    func testFitRejectsTooFewOrScattered() {
        guard case .failure(.tooFewSamples) = CalibrationFit.axis([.init(units: 1, landed: 0)]) else { return XCTFail() }
        let noisy = [(0.12, 0.12), (0.5, 0.56), (0.88, 0.88)].map { CalibrationFit.Sample(units: Int($0.0 * 32767), landed: $0.1) }
        guard case .failure(.scattered) = CalibrationFit.axis(noisy) else { return XCTFail("expected scattered") }
    }

    func testUnitsClamp() {
        let axis = Calibration.Axis(a: 1, b: 0.1)
        XCTAssertEqual(axis.units(for: 0), 0)
        XCTAssertEqual(axis.units(for: 2), 32767)
    }

    /// Whole calibration run against the mock stick: each tap "lands" through a distorted screen mapping.
    func testCalibratorRunFitsAndVerifies() async throws {
        let board = MockBoard()
        let hands = Hands(channel: board.commands)
        let calibrator = Calibrator()
        board.onCommand = { c in
            guard c.name == "tap", c.ints.count >= 2 else { return }
            let ux = Double(c.ints[0]) / 32767, uy = Double(c.ints[1]) / 32767
            calibrator.probe.record(CGPoint(x: 1.02 * ux - 0.01, y: 0.98 * uy + 0.015))
        }
        await calibrator.run(hands: hands, screen: CGSize(width: 390, height: 844))
        guard case let .done(worst) = calibrator.phase else { return XCTFail("phase \(calibrator.phase)") }
        XCTAssertLessThan(worst, 0.002)
        XCTAssertEqual(hands.calibration.x.a, 1.02, accuracy: 0.001)
        XCTAssertTrue(hands.calibration.verified)
        CalibrationStore.clear()
    }

    func testCalibratorFailsWhenTapsMiss() async {
        let board = MockBoard()
        let calibrator = Calibrator()
        calibrator.tapTimeout = 0.2
        await calibrator.run(hands: Hands(channel: board.commands), screen: .zero)
        guard case .failed = calibrator.phase else { return XCTFail("expected failure") }
        XCTAssertTrue(board.sent.contains("key esc"))
    }
}

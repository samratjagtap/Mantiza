import CoreGraphics
import Foundation
import Observation

/// Calibration run: the stick taps a 3x3 grid on the calibration screen, the probe records where each tap
/// lands, a line is fitted per axis, then five other points must land within 1% of the screen.
@MainActor @Observable final class Calibrator {
    enum Phase: Equatable {
        case idle, fitting(Int, Int), checking(Int, Int)
        case done(Double)
        case failed(String)
    }

    private(set) var phase = Phase.idle
    let probe = TouchProbe()
    @ObservationIgnored var tapTimeout = 3.0

    var running: Bool {
        switch phase { case .fitting, .checking: return true; default: return false }
    }

    /// Runs the whole calibration; on success the result is applied to `hands` and saved.
    func run(hands: Hands, screen: CGSize) async {
        probe.reset()
        do {
            let fitted = try await fit(hands)
            var c = fitted
            c.screen = screen
            let worst = try await check(hands, with: c)
            c.worstError = worst
            c.date = Date()
            guard worst <= CalibrationFit.tolerance else {
                return finish(.failed(String(format: "Taps landed up to %.1f%% off. Calibrate again.", worst * 100)))
            }
            hands.calibration = c
            CalibrationStore.save(c)
            finish(.done(worst))
        } catch is CancellationError {
            phase = .idle
        } catch {
            finish(.failed(error.localizedDescription))
        }
    }

    private func finish(_ p: Phase) {
        phase = p
        switch p {
        case let .done(worst): Log.event("calibration.done", ["worst": worst])
        case let .failed(why): Log.event("calibration.failed", ["why": why])
        default: break
        }
    }

    /// Tap at raw units (no calibration) and return where it landed.
    private func probeTap(_ hands: Hands, units: (Int, Int)) async throws -> CGPoint {
        let sent = Date()
        try await hands.channel.send(.tap(units.0, units.1))
        try await hands.channel.send(.park)
        guard let p = await probe.tap(since: sent, timeout: tapTimeout) else {
            _ = try? await hands.channel.send(.key("esc"))  // probably opened the AssistiveTouch menu
            throw CalibrationError("A tap did not reach the screen. Move the AssistiveTouch button to a corner and try again.")
        }
        try Task.checkCancellation()
        return p
    }

    private func fit(_ hands: Hands) async throws -> Calibration {
        var xs: [CalibrationFit.Sample] = [], ys: [CalibrationFit.Sample] = []
        for (i, target) in CalibrationFit.grid.enumerated() {
            phase = .fitting(i, CalibrationFit.grid.count)
            let units = Calibration.identity.units(target)
            let p = try await probeTap(hands, units: units)
            Log.event("calibration.sample", ["ux": units.0, "uy": units.1, "x": p.x, "y": p.y])
            xs.append(.init(units: units.0, landed: p.x))
            ys.append(.init(units: units.1, landed: p.y))
        }
        switch (CalibrationFit.axis(xs), CalibrationFit.axis(ys)) {
        case let (.success(x), .success(y)): return Calibration(x: x, y: y)
        case let (.failure(e), _), let (_, .failure(e)): throw CalibrationError(Self.describe(e))
        }
    }

    private func check(_ hands: Hands, with c: Calibration) async throws -> Double {
        var landed: [CGPoint] = []
        for (i, target) in CalibrationFit.checks.enumerated() {
            phase = .checking(i, CalibrationFit.checks.count)
            landed.append(try await probeTap(hands, units: c.units(target)))
        }
        return CalibrationFit.worstError(aimed: CalibrationFit.checks, landed: landed)
    }

    static func describe(_ e: CalibrationFit.Failure) -> String {
        switch e {
        case let .tooFewSamples(n): return "Only \(n) taps arrived. Calibrate again."
        case let .slope(a):
            return String(format: "The pointer moved %.0f%% of the expected distance. Is Display Zoom or pointer acceleration on?", a * 100)
        case let .scattered(e): return String(format: "Taps were inconsistent (up to %.1f%% off). Calibrate again.", e * 100)
        }
    }
}

struct CalibrationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

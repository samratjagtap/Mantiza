import CoreGraphics
import Foundation

/// Maps screen fractions (0...1, portrait, top-left origin) to the stick's absolute units (0...32767).
/// With the absolute pointer the mapping is linear per axis: landed = a * (units / 32767) + b.
struct Calibration: Codable, Equatable {
    struct Axis: Codable, Equatable {
        var a = 1.0
        var b = 0.0

        /// Units to send so the pointer lands at `fraction`.
        func units(for fraction: Double) -> Int {
            let u = (fraction - b) / a * Double(BoardCommand.unitMax)
            return min(max(Int(u.rounded()), 0), BoardCommand.unitMax)
        }

        func landed(units: Int) -> Double { a * Double(units) / Double(BoardCommand.unitMax) + b }
    }

    var x = Axis()
    var y = Axis()
    /// Worst verification error (fraction of the screen), nil until verified.
    var worstError: Double?
    var screen = CGSize.zero
    var date = Date()

    static let identity = Calibration()

    func units(_ p: CGPoint) -> (Int, Int) { (x.units(for: Double(p.x)), y.units(for: Double(p.y))) }
    var verified: Bool { worstError.map { $0 <= CalibrationFit.tolerance } ?? false }
}

enum CalibrationFit {
    /// Grid the stick taps while the probe records where the taps land.
    static let grid: [CGPoint] = [0.12, 0.5, 0.88].flatMap { y in [0.12, 0.5, 0.88].map { CGPoint(x: $0, y: y) } }
    /// Different points, checked after the fit.
    static let checks: [CGPoint] = [CGPoint(x: 0.25, y: 0.3), CGPoint(x: 0.75, y: 0.3), CGPoint(x: 0.5, y: 0.66),
                                    CGPoint(x: 0.3, y: 0.8), CGPoint(x: 0.7, y: 0.75)]
    static let tolerance = 0.01
    static let slopes = 0.85...1.15

    struct Sample: Equatable {
        var units: Int
        var landed: Double
    }

    enum Failure: Error, Equatable {
        case tooFewSamples(Int)
        case slope(Double)
        case scattered(Double)
    }

    /// Least-squares line through (units / max, landed); refuses a slope far from 1 (the pointer is not absolute,
    /// or taps hit something else) or a poor fit.
    static func axis(_ samples: [Sample]) -> Result<Calibration.Axis, Failure> {
        guard samples.count >= 3 else { return .failure(.tooFewSamples(samples.count)) }
        let xs = samples.map { Double($0.units) / Double(BoardCommand.unitMax) }, ys = samples.map(\.landed)
        let n = Double(samples.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = zip(xs, xs).map { ($0 - mx) * ($1 - mx) }.reduce(0, +)
        guard sxx > 1e-9 else { return .failure(.tooFewSamples(samples.count)) }
        let sxy = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        let a = sxy / sxx, b = my - a * mx
        guard slopes.contains(a) else { return .failure(.slope(a)) }
        let worst = zip(xs, ys).map { abs(a * $0 + b - $1) }.max() ?? 0
        guard worst <= tolerance * 1.5 else { return .failure(.scattered(worst)) }
        return .success(.init(a: a, b: b))
    }

    /// Largest distance on either axis between where we aimed and where the taps landed.
    static func worstError(aimed: [CGPoint], landed: [CGPoint]) -> Double {
        zip(aimed, landed).map { max(abs($0.x - $1.x), abs($0.y - $1.y)) }.map(Double.init).max() ?? .infinity
    }
}

/// The saved calibration for this screen size (Display Zoom changes the size and needs a new one).
enum CalibrationStore {
    private static let key = "calibration"

    static func load(screen: CGSize) -> Calibration? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let c = try? JSONDecoder().decode(Calibration.self, from: data), c.screen == screen else { return nil }
        return c
    }

    static func save(_ c: Calibration) {
        if let data = try? JSONEncoder().encode(c) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

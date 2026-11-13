import SwiftUI

/// The pixel grids of the logo and the wordmark, taken from images/o1-gridded.svg,
/// images/o5-favicon-8x8.svg and images/o6-lockup.svg. M = magenta, G = green, . = empty.
public enum Logo {
    /// The mantis head (12 × 11).
    public static let head = [
        "G..........G",
        ".G........G.",
        "..G......G..",
        "MMMMMMMMMMMM",
        "MGGMMMMMMGGM",
        "MGGMMMMMMGGM",
        ".MMMMMMMMMM.",
        "..MMMMMMMM..",
        "...MMMMMM...",
        "....MMMM....",
        ".....MM.....",
    ]

    /// The small head (8 × 8), for tiny places (lock screen).
    public static let small = [
        "G......G",
        ".G....G.",
        "MMMMMMMM",
        "GGMMMMGG",
        "MMMMMMMM",
        ".MMMMMM.",
        "..MMMM..",
        "...MM...",
    ]

    /// 5 × 7 pixel letters in the style of the lockup.
    static let font: [Character: [String]] = [
        "M": ["X...X", "XX.XX", "X.X.X", "X.X.X", "X...X", "X...X", "X...X"],
        "A": [".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
        "N": ["X...X", "XX..X", "X.X.X", "X..XX", "X...X", "X...X", "X...X"],
        "T": ["XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.."],
        "I": [".XXX.", "..X..", "..X..", "..X..", "..X..", "..X..", ".XXX."],
        "Z": ["XXXXX", "....X", "...X.", "..X..", ".X...", "X....", "XXXXX"],
    ]

    /// "MANTIZA" as one grid, letters one pixel apart, the Z green.
    public static let wordmark: [String] = {
        let word = Array("MANTIZA")
        return (0..<7).map { row in
            word.enumerated().map { i, ch in
                let colour = ch == "Z" ? "G" : "M"
                return (font[ch]?[row] ?? ".....").replacingOccurrences(of: "X", with: colour)
            }.joined(separator: ".")
        }
    }()
}

/// What the head is doing, for its animation.
public enum Mood: Equatable {
    case idle       // antennae twinkle, eyes blink now and then
    case working    // a scan wave runs across the head
    case done       // glows green for a moment
    case failed     // dims
    case greeting   // app start: the antennae flick and the eyes blink twice, in about a second
}

/// Draws a pixel grid crisply at any size (square pixels with small gaps, like the logo), with
/// Mantiza's own animations for each mood (and, if asked, pixels that assemble on first show).
public struct PixelArt: View {
    let grid: [String]
    let mood: Mood
    let animated: Bool
    let assemble: Bool
    @State private var born = Date()
    @State private var moodSince = Date()

    public init(_ grid: [String] = Logo.head, mood: Mood = .idle, animated: Bool = true, assemble: Bool = false) {
        self.grid = grid
        self.mood = mood
        self.animated = animated
        self.assemble = assemble
    }

    public var body: some View {
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    canvas(age: ctx.date.timeIntervalSince(born), moodAge: ctx.date.timeIntervalSince(moodSince))
                }
            } else {
                canvas(age: 100, moodAge: 100)
            }
        }
        .aspectRatio(CGFloat(grid.first?.count ?? 1) / CGFloat(max(grid.count, 1)), contentMode: .fit)
        .onChange(of: mood) { _, _ in moodSince = Date() }
        .accessibilityHidden(true)
    }

    private func canvas(age: Double, moodAge: Double) -> some View {
        Canvas { gc, size in
            let rows = grid.count, cols = grid.first?.count ?? 1
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let gap = cell * 0.125
            let ox = (size.width - cell * CGFloat(cols)) / 2
            let oy = (size.height - cell * CGFloat(rows)) / 2
            for (y, row) in grid.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    let style = pixel(ch: ch, x: x, y: y, rows: rows, age: age, moodAge: moodAge)
                    guard style.alpha > 0.01 else { continue }
                    let rect = CGRect(x: ox + CGFloat(x) * cell + gap / 2, y: oy + CGFloat(y) * cell + gap / 2,
                                      width: cell - gap, height: cell - gap)
                    gc.fill(Path(rect), with: .color(style.color.opacity(style.alpha)))
                }
            }
        }
    }

    private func pixel(ch: Character, x: Int, y: Int, rows: Int, age: Double, moodAge: Double) -> (color: Color, alpha: Double) {
        var color = ch == "G" ? Theme.green : Theme.magenta
        var alpha = 1.0
        // Assemble: pixels arrive in a diagonal sweep the first time the art shows.
        if assemble {
            let delay = Double(x + y) * 0.03
            alpha *= min(max((age - delay) / 0.14, 0), 1)
        }
        guard grid == Logo.head || grid == Logo.small else { return (color, alpha) }
        let antenna = ch == "G" && y < (grid == Logo.head ? 3 : 2)
        let eye = ch == "G" && !antenna
        switch mood {
        case .idle:
            if antenna { alpha *= 0.6 + 0.4 * (0.5 + 0.5 * sin(age * 2.6 - Double(y) * 1.3)) }
            // A blink every 4.5 s: the eyes go magenta for a moment.
            if eye, age.truncatingRemainder(dividingBy: 4.5) > 4.32 { color = Theme.magenta }
        case .working:
            // A scan wave runs down the head; antennae send signals upward.
            let wave = 0.5 + 0.5 * sin(age * 7 - Double(y) * 0.9 - Double(x) * 0.25)
            if ch == "M" { alpha *= 0.45 + 0.55 * wave }
            if antenna { alpha *= 0.3 + 0.7 * (0.5 + 0.5 * sin(age * 9 + Double(y) * 1.6)) }
        case .done:
            // Glow green, then settle.
            let k = max(0, 1 - moodAge / 1.2)
            if ch == "M", k > 0, Int(moodAge * 10) % 2 == 0 || moodAge > 0.4 {
                color = k > 0.5 ? Theme.green : Theme.magenta
            }
        case .greeting:
            // Antennae flick upward fast; the eyes shut twice (0.22 s and 0.52 s in), then stay open.
            if antenna { alpha *= 0.35 + 0.65 * (0.5 + 0.5 * sin(age * 14 + Double(y) * 1.6)) }
            if eye, (0.22..<0.34).contains(age) || (0.52..<0.64).contains(age) { color = Theme.magenta }
        case .failed:
            if ch == "M" { alpha *= 0.45 }
            if eye { color = Theme.magenta; alpha *= 0.6 }
        }
        return (color, alpha)
    }
}

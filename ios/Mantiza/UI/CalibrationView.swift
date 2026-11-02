import SwiftUI

/// Full-screen calibration board: a white grid that catches every tap, while the stick taps known points.
struct CalibrationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var onFinished: (Bool) -> Void = { _ in }
    @State private var task: Task<Void, Never>?

    private var calibrator: Calibrator { app.calibrator }

    var body: some View {
        ZStack {
            Color.white
            GridLines().stroke(Color.gray.opacity(0.25), lineWidth: 1)
            TouchCatcherView(probe: calibrator.probe)
            GeometryReader { geo in
                ForEach(Array(calibrator.probe.hits.enumerated()), id: \.offset) { _, p in
                    Circle().fill(.green.opacity(0.6)).frame(width: 14, height: 14)
                        .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                }
            }
            .allowsHitTesting(false)
            VStack(spacing: 12) {
                Text(title).font(.title3.bold())
                Text(detail).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                if !calibrator.running {
                    HStack {
                        Button(doneButton) { close() }.buttonStyle(.bordered)
                        if !isDone { Button("Start") { start() }.buttonStyle(.borderedProminent) }
                    }
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 40)
            .foregroundStyle(.black)
            .allowsHitTesting(!calibrator.running)  // the grid's centre point lands under this card
            if calibrator.running {  // top corner: no calibration point is that close to the edge
                Button("Stop") { task?.cancel() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 24).padding(.trailing, 16)
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
        .statusBarHidden()
    }

    private var isDone: Bool { if case .done = calibrator.phase { return true }; return false }

    private var title: String {
        switch calibrator.phase {
        case .idle: return "Calibrate the pointer"
        case let .fitting(i, n): return "Measuring \(i + 1) of \(n)"
        case let .checking(i, n): return "Checking \(i + 1) of \(n)"
        case .done: return "Calibrated"
        case .failed: return "Calibration failed"
        }
    }

    private var detail: String {
        switch calibrator.phase {
        case .idle: return "The stick will tap 14 points on this screen. Don't touch the phone until it finishes."
        case .fitting, .checking: return "Hands off the screen, please."
        case let .done(worst): return String(format: "Taps land within %.1f%% of the target.", worst * 100)
        case let .failed(why): return why
        }
    }

    private var doneButton: String { isDone ? "Done" : "Cancel" }

    private func start() {
        task = Task { await calibrator.run(hands: app.hands, screen: Screen.size) }
    }

    private func close() {
        task?.cancel()
        onFinished(isDone)
        dismiss()
    }
}

/// Lines every 10% of the screen.
struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 1..<10 {
            let x = rect.width * CGFloat(i) / 10, y = rect.height * CGFloat(i) / 10
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: rect.height))
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return p
    }
}

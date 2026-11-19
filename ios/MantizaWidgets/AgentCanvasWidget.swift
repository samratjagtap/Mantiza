import SwiftUI
import UIKit
import WidgetKit

struct CanvasEntry: TimelineEntry {
    let date: Date
    let canvas: AgentCanvas
    let thumbnail: UIImage?
}

struct CanvasProvider: TimelineProvider {
    func placeholder(in context: Context) -> CanvasEntry {
        var c = AgentCanvas()
        c.phase = .working
        c.session = true
        c.request = "Order a burrito bowl on Uber Eats"
        c.status = "Tapping “Chipotle”"
        c.step = 3
        c.total = 20
        c.steps = [.init(id: 1, text: "Opened Uber Eats"), .init(id: 2, text: "Searched Chipotle"), .init(id: 3, text: "Tapping “Chipotle”")]
        return CanvasEntry(date: .now, canvas: c, thumbnail: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CanvasEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    /// The app reloads this widget as the agent works; the hourly refresh only keeps suggestions fresh.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CanvasEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(3600))))
    }

    private func entry() -> CanvasEntry {
        let c = AgentCanvas.load()
        let showsScreen = c.phase != .idle && Date().timeIntervalSince(c.updated) < 3600
        let image = showsScreen ? AgentCanvas.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) } : nil
        return CanvasEntry(date: .now, canvas: c, thumbnail: image)
    }
}

/// The agent's own page: what it heard, what it is doing, the screen it sees, and what it got done.
struct AgentCanvasWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AgentCanvas.kind, provider: CanvasProvider()) { entry in
            AgentCanvasView(entry: entry).containerBackground(for: .widget) { CanvasBackground() }
        }
        .configurationDisplayName("Mantiza agent")
        .description("Follow Mantiza as it works: what it heard, each step, and the result.")
        .supportedFamilies([.systemExtraLargePortrait, .systemLarge, .accessoryRectangular])
    }
}

private struct CanvasBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.04, green: 0.18, blue: 0.15), Color(red: 0.05, green: 0.33, blue: 0.27)],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct AgentCanvasView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CanvasEntry
    private var c: AgentCanvas { entry.canvas }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Mantiza · \(c.phase.title)", systemImage: phaseSymbol).font(.caption2.bold())
                Text(c.question ?? (c.status.isEmpty ? c.request : c.status)).font(.caption).lineLimit(2)
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                header
                headline
                stepList(limit: 4)
                Spacer(minLength: 0)
                if let card = c.card { cardView(card) } else { sessionLine }
            }
            .foregroundStyle(.white)
        default:
            VStack(alignment: .leading, spacing: 14) {
                header
                headline
                if let q = c.question { questionView(q) }
                HStack(alignment: .top, spacing: 12) {
                    if let image = entry.thumbnail {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .frame(maxWidth: 130, maxHeight: 280)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.25)))
                    }
                    stepList(limit: 6)
                }
                if let card = c.card { cardView(card) }
                Spacer(minLength: 0)
                suggestions
                sessionLine
            }
            .foregroundStyle(.white)
        }
    }

    private var phaseSymbol: String {
        switch c.phase {
        case .idle: return "hand.tap"
        case .listening: return "waveform"
        case .working: return "gearshape.2"
        case .waiting: return "questionmark.bubble"
        case .done: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var phaseColor: Color {
        switch c.phase {
        case .idle: return .gray
        case .listening: return .purple
        case .working: return .blue
        case .waiting: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }

    private var header: some View {
        HStack {
            Label("Mantiza", systemImage: "hand.tap.fill").font(.headline)
            Spacer()
            Label(c.phase.title, systemImage: phaseSymbol)
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(phaseColor.opacity(0.85), in: Capsule())
        }
    }

    @ViewBuilder private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            if c.request.isEmpty {
                Text("Hold A on the stick and say what to do.").font(.title3.weight(.semibold))
            } else {
                Text(c.request).font(.title3.weight(.semibold)).lineLimit(2)
            }
            if !c.status.isEmpty && c.phase == .working {
                Text(c.status).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
            if c.phase == .working && c.total > 0 {
                ProgressView(value: Double(min(c.step, c.total)), total: Double(c.total)).tint(.mint)
            }
        }
    }

    private func questionView(_ q: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.bubble.fill").font(.title3)
            VStack(alignment: .leading) {
                Text(q).font(.callout.weight(.semibold))
                Text("Answer on the stick: hold A and speak, or A = yes, B = no.").font(.caption2).opacity(0.8)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func stepList(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(c.steps.suffix(limit).enumerated()), id: \.element.id) { i, step in
                let last = i == min(limit, c.steps.count) - 1
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: last && c.phase == .working ? "circle.dotted" : "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(last && c.phase == .working ? .mint : .white.opacity(0.6))
                    Text(step.text).font(.caption).lineLimit(2).opacity(last ? 1 : 0.75)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardView(_ card: AgentCanvas.Card) -> some View {
        HStack(spacing: 12) {
            Image(systemName: card.symbol).font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.headline).font(.headline)
                Text(card.detail).font(.caption).opacity(0.85).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var suggestions: some View {
        if !c.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested now").font(.caption.bold()).opacity(0.7)
                ForEach(c.suggestions.prefix(3)) { item in
                    Link(destination: WidgetSnapshot.runURL(item.id)) {
                        HStack {
                            Text(item.name).font(.callout).lineLimit(1)
                            Spacer()
                            Image(systemName: "play.circle.fill")
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    @ViewBuilder private var sessionLine: some View {
        if c.session {
            Label("Session on · hold A on the stick to talk", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption).opacity(0.75)
        } else {
            Link(destination: AgentCanvas.sessionURL) {
                Label("Tap to start a session", systemImage: "play.circle").font(.caption.bold())
            }
        }
    }
}

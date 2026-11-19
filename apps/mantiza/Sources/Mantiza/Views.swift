import MantizaKit
import SwiftUI

// Mantiza's screens: minimal and calm. Plain dark background, clean system type, soft cards,
// magenta only for the main action, green only for "connected / done", and the pixel head as the
// one decorative element.

// MARK: - Building blocks

/// A small grey label above a group ("STEPS", "STICKS3").
struct Label2: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(11, .medium))
            .tracking(1.2)
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }
}

/// A group of rows on a soft card, like iOS Settings. Rows are separated by hairlines.
struct Card<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Label2(title) }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 16) }
                        row
                    }
                }
            }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            if let footer {
                Text(footer).font(Theme.sans(12)).foregroundStyle(Theme.dim).padding(.horizontal, 4)
            }
        }
    }
}

/// "Battery ............ 84%" with an optional status dot.
struct Row: View {
    let key: String
    let value: String
    var dot: Bool?
    var body: some View {
        HStack(spacing: 10) {
            Text(key).font(Theme.sans(15)).foregroundStyle(Theme.text)
            Spacer(minLength: 12)
            if let dot { Dot(on: dot) }
            Text(value).font(Theme.sans(15)).foregroundStyle(Theme.dim).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

/// A tappable row inside a card ("Connect again").
struct ActionRow: View {
    let title: String
    var color = Theme.text
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.sans(15, .medium))
                .foregroundStyle(color.opacity(enabled ? 1 : 0.35))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressRow())
    }
}

struct PressRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Theme.raised : .clear)
    }
}

/// A small round status dot; it breathes while something is in progress.
struct Dot: View {
    let on: Bool
    var color: Color? = nil
    var pulse = false
    @State private var dim = false
    var body: some View {
        Circle()
            .fill(color ?? (on ? Theme.green : Theme.dim.opacity(0.6)))
            .frame(width: 7, height: 7)
            .opacity(pulse && dim ? 0.3 : 1)
            .onAppear {
                guard pulse else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever()) { dim = true }
            }
    }
}

/// Full-width buttons: filled (the main action) or quiet.
struct MainButton: ButtonStyle {
    var filled = true
    var color = Theme.magenta
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(15, .semibold))
            .foregroundStyle(filled ? .white : Theme.text)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(filled ? color : Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
    }
}

/// A screen's title ("Device", "Log").
struct ScreenTitle: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.sans(30, .bold)).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject var link: DeviceLink

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle(text: "Log").padding(.bottom, 14)
                if link.log.isEmpty {
                    Text("Nothing yet.").font(Theme.sans(15)).foregroundStyle(Theme.dim)
                }
                ForEach(link.log) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(line.time, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                            .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        Text(line.text).font(Theme.mono(12)).foregroundStyle(Theme.text.opacity(0.85))
                    }
                    .padding(.vertical, 7)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Theme.ink.ignoresSafeArea())
    }
}

// MARK: - Boot

/// App start: the head is there at once, flicks its antennae and blinks twice (~1 s), then the app.
struct BootView: View {
    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            PixelArt(Logo.head, mood: .greeting).frame(height: 96)
        }
    }
}

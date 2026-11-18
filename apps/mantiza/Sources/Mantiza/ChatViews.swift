import MantizaKit
import SwiftUI

// The Task tab as a chat: your requests on the right, Mantiza's answers on the left with the steps
// it took folded under a line ("6 steps · 14.2 s"), the field pinned at the bottom (empty again once
// a task starts), and every chat kept in History.

// MARK: - Chat

struct TaskView: View {
    @EnvironmentObject var agent: Agent
    @EnvironmentObject var chats: ChatStore
    @EnvironmentObject var approvals: Approvals
    @EnvironmentObject var link: DeviceLink
    @EnvironmentObject var listener: Listener
    @Binding var request: String
    @FocusState private var typing: Bool
    @State private var showHistory = false
    /// What you usually ask around now first, then recent tasks, then starters.
    @State private var ideas: [Shared.Suggestion] = []

    private var empty: Bool { request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if chats.messages.isEmpty { welcome }
                        ForEach(Array(chats.messages.enumerated()), id: \.element.id) { i, m in
                            MessageView(message: m,
                                        request: i > 0 && chats.messages[i - 1].role == .user ? chats.messages[i - 1].text : nil)
                                .id(m.id)
                        }
                        question
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .animation(.easeOut(duration: 0.2), value: approvals.question)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chats.openID) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chats.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: agent.steps.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: approvals.question) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            input
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 8)
        }
        .background(Theme.ink.ignoresSafeArea())
        .sheet(isPresented: $showHistory) { HistoryView() }
        .onAppear { ideas = Shared.suggestions(count: 4) }
        // A task started (typed, the mic, Siri, the widget): the field is empty again, like a chat.
        .onChange(of: agent.running) { _, running in
            if running { request = "" } else { ideas = Shared.suggestions(count: 4) }
        }
        // While listening, the words appear in the field as they are heard.
        .onChange(of: listener.heard) { _, heard in if listener.listening { request = heard } }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { typing = false; showHistory = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Chats")
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(chats.open?.title ?? "New chat")
                    .font(Theme.sans(15, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Dot(on: link.ready, pulse: !link.ready)
                    Text(link.ready ? "Connected" : "No device").font(Theme.sans(11)).foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
            Button { chats.newChat(); request = "" } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text.opacity(agent.running || chats.openID == nil ? 0.3 : 1))
                    .frame(width: 36, height: 36)
            }
            .disabled(agent.running || chats.openID == nil)
            .accessibilityLabel("New chat")
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5).opacity(chats.messages.isEmpty ? 0 : 1) }
    }

    private var welcome: some View {
        VStack(spacing: 26) {
            VStack(spacing: 16) {
                PixelArt(Logo.head, mood: listener.listening ? .working : .idle).frame(height: 64)
                Text(listener.listening ? "Listening…" : (listener.problem ?? "What can I do on your phone?"))
                    .font(Theme.sans(20, .semibold))
                    .foregroundStyle(listener.problem != nil ? Theme.magenta : Theme.text)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            if !ideas.isEmpty {
                VStack(spacing: 8) {
                    ForEach(ideas, id: \.self) { idea in
                        Button { request = idea.prompt; typing = true } label: {
                            HStack(spacing: 8) {
                                if idea.habit { Image(systemName: "clock").font(.system(size: 12)).foregroundStyle(Theme.green) }
                                Text(idea.prompt).font(Theme.sans(14)).foregroundStyle(Theme.text.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 70)
    }

    // One rounded field with the send (or stop) button inside it.
    private var input: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: $request, prompt: Text(listener.listening ? "Listening…" : "Ask Mantiza…").foregroundStyle(Theme.dim),
                      axis: .vertical)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.text)
                .tint(Theme.magenta)
                .lineLimit(1...5)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.vertical, 7)
            // One button: stop while a task runs; the microphone while the field is empty (or
            // while listening); send once there is text.
            let mic = !agent.running && (empty || listener.listening)
            Button {
                if agent.running { agent.stop() } else if mic { typing = false; listener.toggle() } else { send() }
            } label: {
                Image(systemName: agent.running ? "stop.fill" : (mic ? "mic.fill" : "arrow.up"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(agent.running ? Theme.ink : .white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(agent.running ? Theme.text : (mic && !listener.listening ? Theme.raised : Theme.magenta)))
                    .scaleEffect(listener.listening ? 1.12 : 1)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: listener.listening)
            }
            .accessibilityLabel(agent.running ? "Stop" : (mic ? (listener.listening ? "Stop listening" : "Speak") : "Send"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(typing ? Theme.magenta.opacity(0.6) : Theme.line, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: typing)
    }

    private func send() {
        guard !agent.running, !empty else { return }
        let text = request
        request = ""
        listener.finish(run: false)
        agent.start(text)
    }

    @ViewBuilder private var question: some View {
        if let q = approvals.question {
            VStack(alignment: .leading, spacing: 14) {
                Text(approvals.choices == nil ? "Needs your OK" : "Which one?")
                    .font(Theme.mono(11, .medium)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.dim)
                Text(q).font(Theme.sans(16)).foregroundStyle(Theme.text)
                if let choices = approvals.choices {
                    ForEach(Array(choices.enumerated()), id: \.offset) { i, c in
                        Button(c) { approvals.pick(i) }.buttonStyle(MainButton(filled: false))
                    }
                    Button("None of these") { approvals.pick(nil) }
                        .font(Theme.sans(14)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 10) {
                        Button("Not now") { approvals.answer(false) }.buttonStyle(MainButton(filled: false))
                        Button("Approve") { approvals.answer(true) }.buttonStyle(MainButton())
                    }
                }
            }
            .padding(16)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.magenta.opacity(0.5), lineWidth: 1))
            .padding(.leading, 34)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

// MARK: - One message

struct MessageView: View {
    @EnvironmentObject var agent: Agent
    @EnvironmentObject var chats: ChatStore
    let message: ChatStore.Message
    /// The request this answer belongs to (for "Again").
    let request: String?
    @State private var showSteps = false
    @State private var openShot: Int?
    @State private var copied = false

    private var working: Bool { message.outcome == .working && agent.running }

    var body: some View {
        if message.role == .user { user } else { mantiza }
    }

    private var user: some View {
        HStack {
            Spacer(minLength: 56)
            Text(message.text)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var mood: Mood {
        switch message.outcome {
        case .working: return working ? .working : .idle
        case .done, .answer: return .idle
        case .failed, .blocked: return .failed
        default: return .idle
        }
    }

    private var failed: Bool { [.failed, .blocked].contains(message.outcome) }

    /// Live while the task runs, saved afterwards.
    private var stepTexts: [String] { working ? agent.steps.map(\.text) : message.steps }
    private var stepImages: [UIImage?] { working ? agent.steps.map(\.image) : (chats.shots[message.id] ?? []) }

    private var mantiza: some View {
        HStack(alignment: .top, spacing: 10) {
            PixelArt(Logo.head, mood: mood, animated: working).frame(width: 24, height: 24).padding(.top, 1)
            VStack(alignment: .leading, spacing: 10) {
                if !stepTexts.isEmpty || working { stepsBlock }
                if working {
                    HStack(spacing: 8) {
                        Dot(on: true, color: Theme.text, pulse: true)
                        Text(agent.status).font(Theme.sans(15)).foregroundStyle(Theme.dim)
                            .contentTransition(.opacity)
                            .animation(.easeOut(duration: 0.2), value: agent.status)
                    }
                } else {
                    Text(message.text.isEmpty ? "…" : message.text)
                        .font(Theme.sans(16))
                        .foregroundStyle(failed ? Theme.magenta : Theme.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    footer
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if let label = outcomeLabel {
                Text(label).font(Theme.mono(11)).foregroundStyle(failed ? Theme.magenta.opacity(0.8) : Theme.dim)
            }
            Button {
                UIPasteboard.general.string = message.text
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            .accessibilityLabel("Copy")
            if let request {
                Button { agent.start(request) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
                .disabled(agent.running)
                .accessibilityLabel("Do it again")
            }
        }
    }

    private var outcomeLabel: String? {
        let time = message.seconds.map { String(format: " · %.1f s", $0) } ?? ""
        switch message.outcome {
        case .done: return "Done" + time
        case .answer: return nil
        case .failed: return "Didn't work" + time
        case .stopped: return "Stopped" + time
        case .unsure: return "Not confirmed" + time
        case .blocked: return "Blocked"
        case .working, .none: return nil
        }
    }

    private var stepsBlock: some View {
        let open = showSteps || working
        return VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.2)) { showSteps.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(working ? "Working" : "\(stepTexts.count) step\(stepTexts.count == 1 ? "" : "s")"
                         + (message.seconds.map { String(format: " · %.1f s", $0) } ?? ""))
                        .font(Theme.sans(13))
                }
                .foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            .disabled(working)
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(stepTexts.enumerated()), id: \.offset) { i, text in
                        let current = working && i == stepTexts.count - 1
                        let bad = text.hasPrefix("❌")
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Dot(on: true, color: bad ? Theme.magenta : (current ? Theme.text : Theme.green.opacity(0.7)), pulse: current)
                                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                Text(text).font(Theme.sans(13))
                                    .foregroundStyle(current ? Theme.text : Theme.text.opacity(0.65))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if i < stepImages.count, stepImages[i] != nil {
                                    Button { withAnimation(.easeOut(duration: 0.2)) { openShot = openShot == i ? nil : i } } label: {
                                        Image(systemName: openShot == i ? "photo.fill" : "photo")
                                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                                    }
                                }
                            }
                            if openShot == i, i < stepImages.count, let image = stepImages[i] {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .padding(.leading, 17)
                            }
                        }
                    }
                }
                .padding(.leading, 4)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .animation(.easeOut(duration: 0.2), value: stepTexts.count)
            }
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject var chats: ChatStore
    @EnvironmentObject var agent: Agent
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var confirmClear = false

    private var found: [ChatStore.Chat] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return chats.chats }
        return chats.chats.filter { c in
            c.title.lowercased().contains(q) || c.messages.contains { $0.text.lowercased().contains(q) }
        }
    }

    /// Today, Yesterday, Previous 7 days, Previous 30 days, then by month.
    private var groups: [(String, [ChatStore.Chat])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [(String, [ChatStore.Chat])] = []
        for chat in found {
            let day = cal.startOfDay(for: chat.updated)
            let ago = cal.dateComponents([.day], from: day, to: today).day ?? 0
            let name: String
            switch ago {
            case ...0: name = "Today"
            case 1: name = "Yesterday"
            case 2...7: name = "Previous 7 days"
            case 8...30: name = "Previous 30 days"
            default: name = chat.updated.formatted(.dateTime.month(.wide).year())
            }
            if let i = out.firstIndex(where: { $0.0 == name }) { out[i].1.append(chat) } else { out.append((name, [chat])) }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { chats.newChat(); dismiss() } label: {
                        Label("New chat", systemImage: "square.and.pencil").foregroundStyle(Theme.text)
                    }
                    .disabled(agent.running)
                }
                .listRowBackground(Theme.panel)
                if chats.chats.isEmpty {
                    Text("Your chats will show here.").font(Theme.sans(14)).foregroundStyle(Theme.dim)
                        .listRowBackground(Color.clear)
                }
                ForEach(groups, id: \.0) { name, list in
                    Section(name) {
                        ForEach(list) { chat in
                            Button { chats.select(chat.id); dismiss() } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chat.title).font(Theme.sans(15)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text(preview(chat)).font(Theme.sans(12)).foregroundStyle(Theme.dim).lineLimit(1)
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowBackground(chat.id == chats.openID ? Theme.raised : Theme.panel)
                            .swipeActions {
                                Button(role: .destructive) { chats.delete(chat.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
            .searchable(text: $search, prompt: "Search chats")
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(role: .destructive) { confirmClear = true } label: { Label("Delete all chats", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .disabled(chats.chats.isEmpty)
                }
            }
            .confirmationDialog("Delete all chats?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { chats.deleteAll() }
            } message: {
                Text("They are removed from this iPhone.")
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.text)
    }

    private func preview(_ chat: ChatStore.Chat) -> String {
        let last = chat.messages.last { $0.role == .mantiza && !$0.text.isEmpty }?.text ?? ""
        let when = chat.updated.formatted(date: .omitted, time: .shortened)
        return last.isEmpty ? when : "\(when) · \(last)"
    }
}

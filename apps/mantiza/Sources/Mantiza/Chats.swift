import Foundation
import UIKit

/// Chats, like a chat app: each request and Mantiza's answer is a message in the open chat; chats
/// are kept on the phone (Application Support/chats.json) and listed in History. Every way a task
/// starts (typed, the mic, Siri, the widget, the Lock Screen) lands here, because the agent records
/// it, not the screen.
@MainActor
final class ChatStore: ObservableObject {
    struct Message: Codable, Identifiable, Hashable {
        enum Role: String, Codable { case user, mantiza }
        enum Outcome: String, Codable { case working, done, answer, failed, stopped, unsure, blocked }

        var id = UUID()
        var role: Role
        var text: String
        var outcome: Outcome?
        var steps: [String] = []
        var seconds: Double?
        var date = Date()
    }

    struct Chat: Codable, Identifiable, Hashable {
        var id = UUID()
        var title: String
        var messages: [Message] = []
        var created = Date()
        var updated = Date()
    }

    @Published private(set) var chats: [Chat] = []       // newest first
    @Published var openID: UUID?                           // nil: a new, empty chat
    /// Screenshots of this session's tasks, by message (not saved: they can show private chats).
    private(set) var shots: [UUID: [UIImage?]] = [:]

    private let keepChats = 200
    private var working: (chat: UUID, message: UUID)?

    private var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chats.json")
    }

    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Chat].self, from: data) {
            chats = saved.map { chat in
                // A task that was cut off (the app closed mid-task) shouldn't look like it's still running.
                var c = chat
                for i in c.messages.indices where c.messages[i].outcome == .working {
                    c.messages[i].outcome = .stopped
                    if c.messages[i].text.isEmpty { c.messages[i].text = "Stopped (Mantiza was closed)" }
                }
                return c
            }
        }
    }

    var open: Chat? { chats.first { $0.id == openID } }
    var messages: [Message] { open?.messages ?? [] }

    func newChat() { openID = nil }

    func select(_ id: UUID) { openID = id }

    func delete(_ id: UUID) {
        chats.removeAll { $0.id == id }
        if openID == id { openID = nil }
        save()
    }

    func deleteAll() {
        chats = []
        openID = nil
        shots = [:]
        save()
    }

    /// The last exchanges of the open chat, oldest first, for the planner (so "send it again" or
    /// "message him too" make sense). Empty for a new chat.
    func context(turns: Int = 6) -> [(request: String, reply: String)] {
        let msgs = messages
        var out: [(String, String)] = []
        var i = 0
        while i < msgs.count {
            if msgs[i].role == .user {
                let reply = i + 1 < msgs.count && msgs[i + 1].role == .mantiza ? msgs[i + 1].text : ""
                out.append((msgs[i].text, reply))
            }
            i += 1
        }
        return Array(out.suffix(turns))
    }

    /// A task starts: the request goes into the open chat (a new chat if none is open), with
    /// Mantiza's answer pending under it.
    func begin(_ request: String) {
        let now = Date()
        var chat: Chat
        if let open { chat = open } else {
            chat = Chat(title: ChatStore.title(for: request))
            openID = chat.id
        }
        chat.messages.append(Message(role: .user, text: request, date: now))
        let answer = Message(role: .mantiza, text: "", outcome: .working, date: now)
        chat.messages.append(answer)
        chat.updated = now
        put(chat)
        working = (chat.id, answer.id)
    }

    /// The task ended: its answer, how it went, and its steps.
    func finish(status: String, reply: String, steps: [(text: String, image: UIImage?)], seconds: Double) {
        guard let w = working, var chat = chats.first(where: { $0.id == w.chat }),
              let i = chat.messages.firstIndex(where: { $0.id == w.message }) else { return }
        working = nil
        let (outcome, text) = ChatStore.outcome(of: status, reply: reply)
        chat.messages[i].outcome = outcome
        chat.messages[i].text = text
        // The last step repeats the result: leave it out of the list.
        var list = steps
        if let last = list.last, last.text == status { list.removeLast() }
        chat.messages[i].steps = list.map(\.text)
        chat.messages[i].seconds = seconds
        chat.updated = Date()
        shots[w.message] = list.map(\.image)
        put(chat)
    }

    // MARK: - Helpers

    private func put(_ chat: Chat) {
        chats.removeAll { $0.id == chat.id }
        chats.insert(chat, at: 0)
        if chats.count > keepChats { chats = Array(chats.prefix(keepChats)) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(chats) { try? data.write(to: file, options: [.atomic, .completeFileProtection]) }
    }

    static func title(for request: String) -> String {
        let t = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 42 else { return t.prefix(1).uppercased() + t.dropFirst() }
        let cut = t.prefix(42)
        let words = cut.split(separator: " ").dropLast()
        let short = words.isEmpty ? String(cut) : words.joined(separator: " ")
        return short.prefix(1).uppercased() + short.dropFirst() + "…"
    }

    /// The agent's status line ("✅ Done in 4.2 s · …", "💬 …", "❌ …") as an outcome and the text to show.
    static func outcome(of status: String, reply: String) -> (Message.Outcome, String) {
        func strip(_ s: String) -> String {
            var t = s
            if let first = t.first, !first.isLetter, !first.isNumber, first != "\"" { t = String(t.drop { !$0.isLetter && !$0.isNumber && $0 != "\"" }) }
            return t.trimmingCharacters(in: .whitespaces)
        }
        if status.hasPrefix("💬") { return (.answer, strip(status)) }
        if status.hasPrefix("✅") {
            let r = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return (.done, r.isEmpty ? "Done." : r)
        }
        if status.hasPrefix("⏹") { return (.stopped, strip(status)) }
        if status.hasPrefix("⛔") { return (.blocked, strip(status)) }
        if status.hasPrefix("❓") { return (.unsure, strip(status)) }
        return (.failed, strip(status))
    }
}

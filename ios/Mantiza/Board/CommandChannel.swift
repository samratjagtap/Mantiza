import Foundation

// Based on ESP32 iPhone Agent by Henry Yuan (await-ovo fork, MIT); see THIRD_PARTY_NOTICES.md.

struct BoardError: LocalizedError, Equatable {
    enum Kind: Equatable { case notConnected, linkLost, timeout, refused }
    let kind: Kind
    let message: String
    var errorDescription: String? { message }

    static let notConnected = BoardError(kind: .notConnected, message: "Mantiza Hands is not connected.")
}

/// Where command lines go: the Bluetooth link, the mock board, or a fake in tests.
@MainActor protocol BoardTransport: AnyObject {
    var isConnected: Bool { get }
    func write(_ line: String) throws
}

/// A FIFO async mutex for main-actor code.
@MainActor final class AsyncLock {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

/// Sends commands one at a time and matches replies by request id; passes device events on.
@MainActor final class CommandChannel {
    weak var transport: BoardTransport?
    var onEvent: ((BoardEvent) -> Void)?
    /// Every command with its result and time, for the run log and the Mac e2e harness.
    var onSent: ((String, Result<String, Error>, Double) -> Void)?
    private(set) var links = 0
    private let lock = AsyncLock()
    /// The board also answers the Mac harness over USB; start our ids far from its small ones.
    private var nextID = Int.random(in: 100_000...800_000)
    private var pending: [Int: CheckedContinuation<BoardReply, Error>] = [:]

    init(transport: BoardTransport? = nil) { self.transport = transport }

    var connected: Bool { transport?.isConnected ?? false }

    func linkUp() { links += 1 }

    /// The link dropped: fail everything in flight.
    func linkDown() {
        let waiting = pending
        pending = [:]
        waiting.values.forEach { $0.resume(throwing: BoardError(kind: .linkLost, message: "Mantiza Hands disconnected.")) }
    }

    func handle(_ line: String) {
        switch BoardLine.parse(line) {
        case let .reply(reply): pending.removeValue(forKey: reply.id)?.resume(returning: reply)
        case let .event(event): onEvent?(event)
        case nil: break
        }
    }

    /// Seconds the board may take to answer.
    nonisolated static func timeout(_ command: BoardCommand) -> Double {
        switch command {
        case let .type(text): return 5 + 0.04 * Double(text.count)  // 2 edges x 15 ms per character
        case let .ask(seconds, _): return Double(min(max(seconds, 1), 120)) + 5
        case let .longPress(_, _, ms): return 5 + Double(ms) / 1000
        default: return 5
        }
    }

    /// Send one command; returns the text after "ok". A timeout keeps the link: the board may just be slow,
    /// and an acting command may already have run, so callers must look at the screen before retrying.
    @discardableResult
    func send(_ command: BoardCommand) async throws -> String {
        guard connected, let transport else { throw BoardError.notConnected }
        let line = command.line
        let timeout = Self.timeout(command)
        await lock.lock()
        defer { lock.unlock() }
        try Task.checkCancellation()
        let started = Date()
        let id = nextID
        nextID += 1
        do {
            let reply = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<BoardReply, Error>) in
                    pending[id] = c
                    do { try transport.write("\(id) \(line)") } catch {
                        pending[id] = nil
                        c.resume(throwing: error)
                        return
                    }
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(timeout))
                        let what = command.acts ? "; it may have run, check the screen before trying again" : ""
                        self?.fail(id, BoardError(kind: .timeout,
                                                  message: "The stick did not answer '\(line.prefix(30))' in \(Int(timeout)) s\(what)."))
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.fail(id, CancellationError()) }
            }
            guard reply.ok else { throw BoardError(kind: .refused, message: "The stick refused '\(line.prefix(30))': \(reply.text)") }
            onSent?(line, .success(reply.text), Date().timeIntervalSince(started) * 1000)
            return reply.text
        } catch {
            onSent?(line, .failure(error), Date().timeIntervalSince(started) * 1000)
            throw error
        }
    }

    private func fail(_ id: Int, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }
}

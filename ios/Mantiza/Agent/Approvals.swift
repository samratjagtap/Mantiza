import Foundation

/// One pending approval at a time, answered by whichever comes first: button A/B on the stick, the Live Activity
/// buttons or the notification. No answer within the timeout counts as "no".
@MainActor final class Approvals {
    private var pending: CheckedContinuation<Bool, Never>?
    private var timer: Task<Void, Never>?
    private(set) var question: String?
    /// Show the question everywhere (stick prompt, Live Activity, notification).
    var onAsk: (String) -> Void = { _ in }
    /// The question is answered; `source` is "stick", "phone" or "timeout".
    var onResolve: (Bool, String) -> Void = { _, _ in }

    func ask(_ q: String, timeout: Double = 60) async -> Bool {
        resolve(false, source: "replaced")  // never two at once
        Log.event("approval.ask", ["text": q])
        return await withCheckedContinuation { c in
            pending = c
            question = q
            onAsk(q)
            timer = Task { [weak self] in
                guard (try? await Task.sleep(for: .seconds(timeout))) != nil else { return }
                self?.resolve(false, source: "timeout")
            }
        }
    }

    func resolve(_ yes: Bool, source: String) {
        guard let c = pending else { return }
        pending = nil
        question = nil
        timer?.cancel()
        Log.event("approval.answer", ["yes": yes, "source": source])
        onResolve(yes, source)
        c.resume(returning: yes)
    }
}

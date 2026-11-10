import Foundation
import UIKit

/// Development only: a report of every task (prompt, plan, steps with screenshots, device log,
/// result) is saved on the phone and sent over Wi-Fi to the debug inbox on the developer's PC
/// (tools/debug-inbox), where `/debug` in Claude Code reads it. Off when the build has no inbox
/// address (Secrets.debugInbox is empty), so user builds never record or send anything.
@MainActor
final class RunLog {
    static let shared = RunLog()

    struct Step: Codable {
        var t: Double          // seconds since the task started
        var text: String
        var image: String?     // file name of its screenshot
    }

    struct Run: Codable {
        var id: String
        var prompt: String
        var started: Date
        var ended: Date?
        var result: String?
        var plan: String?
        var steps: [Step] = []
        var deviceLog: [String] = []
        var build: String
        var device: String
    }

    var enabled: Bool { !Secrets.debugInbox.isEmpty }

    private var current: Run?
    private var images: [String: Data] = [:]
    private var flushing = false

    private var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("runs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func begin(_ prompt: String) {
        guard enabled else { return }
        let d = UIDevice.current
        current = Run(id: UUID().uuidString, prompt: prompt, started: Date(), build: Secrets.build,
                      device: "\(d.model) iOS \(d.systemVersion), screen \(Int(UIScreen.main.bounds.width))×\(Int(UIScreen.main.bounds.height)) pt")
        images = [:]
    }

    func plan(_ plan: Plan) {
        guard current != nil, let data = try? JSONEncoder().encode(plan) else { return }
        current?.plan = String(decoding: data, as: UTF8.self)
    }

    func step(_ text: String, image: UIImage?) {
        guard var run = current else { return }
        var name: String?
        if let image, let jpeg = image.jpegData(compressionQuality: 0.6) {
            name = String(format: "step-%02d.jpg", run.steps.count + 1)
            images[name!] = jpeg
        }
        run.steps.append(Step(t: Date().timeIntervalSince(run.started), text: text, image: name))
        current = run
    }

    /// Saves the finished run on the phone and tries to send it (and any earlier unsent ones).
    func finish(result: String, deviceLog: [LogLine]) {
        guard var run = current else { return }
        current = nil
        run.ended = Date()
        run.result = result
        run.deviceLog = deviceLog.filter { $0.time >= run.started }.reversed().map {
            String(format: "%6.2f ", $0.time.timeIntervalSince(run.started)) + $0.text
        }
        let dir = folder.appendingPathComponent(run.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(run).write(to: dir.appendingPathComponent("run.json"))
        for (name, data) in images { try? data.write(to: dir.appendingPathComponent(name)) }
        images = [:]
        Task { await flush() }
    }

    /// Sends every saved run that hasn't reached the inbox yet. Called after each task and when
    /// the app comes to the front; runs wait on the phone while the PC is off.
    func flush() async {
        guard enabled, !flushing, let url = URL(string: Secrets.debugInbox + "/runs") else { return }
        flushing = true
        defer { flushing = false }
        let fm = FileManager.default
        let dirs = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for dir in dirs {
            let sent = dir.appendingPathComponent("sent")
            if fm.fileExists(atPath: sent.path) {
                // Keep sent runs a week, then free the space.
                if let made = try? sent.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   Date().timeIntervalSince(made) > 7 * 86400 { try? fm.removeItem(at: dir) }
                continue
            }
            guard let runData = try? Data(contentsOf: dir.appendingPathComponent("run.json")),
                  let run = try? JSONSerialization.jsonObject(with: runData) else { continue }
            var files: [String: String] = [:]
            for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasSuffix(".jpg") {
                files[f] = (try? Data(contentsOf: dir.appendingPathComponent(f)))?.base64EncodedString()
            }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(Secrets.debugToken, forHTTPHeaderField: "X-Mantiza-Token")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["run": run, "images": files])
            guard let (_, response) = try? await URLSession.shared.data(for: req),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }  // PC not reachable: try later
            fm.createFile(atPath: sent.path, contents: nil)
        }
    }
}

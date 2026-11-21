import Foundation
import Network

/// Finds the Laya server on this Wi-Fi: tools/laya/serve.sh advertises `_mantiza-laya._tcp` with the Mac's
/// `.local` name, which keeps working when the Mac's IP address changes. Looks once per launch, then again when
/// the saved address could not be reached (on coming to the front, or right after the failed step).
@MainActor enum LayaFinder {
    static let type = "_mantiza-laya._tcp"
    private static var browser: NWBrowser?
    private static var lastTry = Date.distantPast
    private static var foundThisLaunch = false

    static func refresh() {
        guard AISettings.fast == .laya, browser == nil, Date().timeIntervalSince(lastTry) > 60,
              !foundThisLaunch || AISettings.layaURL.isEmpty || Reachability.isDown("laya") else { return }
        lastTry = Date()
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { results, _ in
            for r in results {
                guard case let .bonjour(txt) = r.metadata, let url = url(txt) else { continue }
                Task { @MainActor in found(url) }
                return
            }
        }
        browser = b
        b.start(queue: .main)
        Task { try? await Task.sleep(for: .seconds(5)); stop() }
    }

    /// `http://<host>:<port>` from the advertised TXT record.
    nonisolated static func url(_ txt: NWTXTRecord) -> String? {
        guard let host = txt["host"], !host.isEmpty, let port = txt["port"].flatMap(Int.init) else { return nil }
        return "http://\(host):\(port)"
    }

    private static func found(_ url: String) {
        guard browser != nil else { return }
        stop()
        foundThisLaunch = true
        if url != AISettings.layaURL { AISettings.layaURL = url }
        Reachability.reset("laya")
        Log.event("laya.found", ["url": url])
    }

    private static func stop() {
        browser?.cancel()
        browser = nil
    }
}

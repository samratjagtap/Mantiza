import CoreBluetooth
import Foundation
import Observation

// Based on ESP32 iPhone Agent by Henry Yuan (await-ovo fork, MIT); see THIRD_PARTY_NOTICES.md.

/// Core Bluetooth central for the stick: scan, connect (bonding happens on the first encrypted status read),
/// command writes, reply and status notifies. Reconnects on its own and restores state when iOS relaunches the app.
///
/// Pairing order matters: the app connects first, then the user pairs the HID pointer in AssistiveTouch.
@MainActor @Observable final class BoardLink: NSObject, BoardTransport {
    struct Found: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    private(set) var bluetooth: CBManagerState = .unknown
    private(set) var found: [Found] = []
    private(set) var scanning = false
    private(set) var connecting = false
    private(set) var connected = false  // subscribed, authenticated and ready for commands
    /// Subscribed; commands can go out (the auth handshake runs on this).
    private(set) var transportReady = false
    /// While a new pairing secret is being set: the code the stick shows, for the user to compare.
    private(set) var pairingCode: String?
    private(set) var pairedID: UUID?
    private(set) var name = ""
    private(set) var status: BoardStatus?
    private(set) var lastError = ""

    @ObservationIgnored let commands = CommandChannel()
    @ObservationIgnored var onLinkUp: (() -> Void)?
    @ObservationIgnored var onLinkDown: (() -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var chars: [CBUUID: CBCharacteristic] = [:]
    @ObservationIgnored private var subscribed = Set<CBUUID>()
    /// Push-to-talk packets from the stick and the key to read them (set once the stick has authenticated us).
    @ObservationIgnored var onAudio: ((Data) -> Void)?
    @ObservationIgnored private(set) var audioKey: Data?
    @ObservationIgnored private var candidates: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var lastNotify = Date.distantPast
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var scanDeadline: Task<Void, Never>?
    @ObservationIgnored private var connectDeadline: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    private static let pairedKey = "pairedBoard"

    override init() {
        super.init()
        pairedID = UserDefaults.standard.string(forKey: Self.pairedKey).flatMap(UUID.init)
        commands.transport = self
    }

    /// Create the central (this shows the Bluetooth permission prompt the first time).
    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "mantiza-central",
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
    }

    var isConnected: Bool { transportReady }
    var inputReady: Bool { connected && status?.inputReady == true }

    // MARK: - scan / pair

    func scan() {
        guard let central, bluetooth == .poweredOn, !connected, !connecting else { return }
        found = []
        lastError = ""
        scanning = true
        central.scanForPeripherals(withServices: [BoardUUID.service], options: nil)
        Log.info("BLE scanning")
        scanDeadline?.cancel()
        scanDeadline = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(15))) != nil, let self, self.scanning else { return }
            self.stopScan()
            if self.found.isEmpty { self.lastError = "No stick found. Turn it on, keep it close, and scan again." }
        }
        // A stick already connected to this phone (for example as its pointer) may not advertise.
        for p in central.retrieveConnectedPeripherals(withServices: [BoardUUID.service]) {
            discovered(p, name: p.name ?? "Mantiza Hands", rssi: 0)
        }
    }

    func stopScan() {
        scanDeadline?.cancel()
        central?.stopScan()
        scanning = false
    }

    /// Connect to a stick and remember it; the first encrypted read then pairs it with this phone.
    func pair(_ id: UUID) {
        stopScan()
        if let previous = peripheral, previous.identifier != id {
            peripheral = nil
            central?.cancelPeripheralConnection(previous)
            setDisconnected()
        }
        pairedID = id
        lastError = ""
        peripheral = candidates[id]
        reconnect()
    }

    /// Ask the stick to erase its bonds, then forget it here. iOS keeps its own bond: the user removes
    /// "Mantiza Hands" in Settings > Bluetooth (apps cannot do that).
    func unpair() async {
        _ = try? await commands.send(.unpair)
        if let id = pairedID { SessionAuth.store(nil, for: id) }
        forget()
    }

    /// Set a new pairing secret (after the user opened the pairing window on the stick).
    func repairAuth() {
        guard let id = pairedID, let p = peripheral, transportReady else { return }
        SessionAuth.store(nil, for: id)
        Task { await authenticate(p) }
    }

    /// Forget the stick in the app only.
    func forget() {
        retry?.cancel()
        let previous = peripheral
        peripheral = nil
        if let previous { central?.cancelPeripheralConnection(previous) }
        pairedID = nil
        status = nil
        UserDefaults.standard.removeObject(forKey: Self.pairedKey)
        setDisconnected()
    }

    private func discovered(_ p: CBPeripheral, name: String, rssi: Int) {
        candidates[p.identifier] = p
        let item = Found(id: p.identifier, name: name, rssi: rssi)
        if let i = found.firstIndex(where: { $0.id == item.id }) { found[i] = item } else { found.append(item) }
        if p.identifier == pairedID && !connected && !connecting {
            stopScan()
            peripheral = p
            reconnect()
        }
    }

    private func reconnect() {
        guard let central, bluetooth == .poweredOn, !connected, !connecting, let id = pairedID else { return }
        if peripheral?.identifier != id { peripheral = central.retrievePeripherals(withIdentifiers: [id]).first }
        guard let peripheral else {
            if !scanning { scan() }  // iOS does not know it yet: find it by scanning, then connect
            return
        }
        peripheral.delegate = self
        name = peripheral.name ?? name
        connecting = true
        Log.info("BLE connecting to \(name)")
        connectDeadline?.cancel()
        connectDeadline = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(30))) != nil, let self, !self.connected else { return }
            self.fail("Connecting timed out. Keep the stick close and try again.")
        }
        if peripheral.state == .connected {
            peripheral.discoverServices([BoardUUID.service])
        } else {
            central.connect(peripheral, options: nil)
        }
    }

    private func fail(_ message: String) {
        retry?.cancel()
        lastError = message
        Log.event("board.error", ["message": message])
        let previous = peripheral
        setDisconnected()
        if let previous { central?.cancelPeripheralConnection(previous) }
    }

    // MARK: - BoardTransport

    func write(_ line: String) throws {
        guard transportReady, let peripheral, let c = chars[BoardUUID.cmd] else { throw BoardError.notConnected }
        let data = Data(line.utf8)
        let fast = data.count <= peripheral.maximumWriteValueLength(for: .withoutResponse)
            && c.properties.contains(.writeWithoutResponse) && peripheral.canSendWriteWithoutResponse
        peripheral.writeValue(data, for: c, type: fast ? .withoutResponse : .withResponse)
    }

    /// The board notifies its status every second, so 5 s of silence means it went away: drop the link now
    /// instead of waiting for the Bluetooth supervision timeout; the pending connect picks it up again.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.connected, let p = self.peripheral else { return }
                if Date().timeIntervalSince(self.lastNotify) > 5 {
                    Log.info("BLE: no status for 5 s, dropping the link")
                    self.central?.cancelPeripheralConnection(p)
                    return
                }
            }
        }
    }

    private func setDisconnected() {
        watchdog?.cancel()
        connectDeadline?.cancel()
        let was = connected
        connecting = false
        connected = false
        transportReady = false
        pairingCode = nil
        chars = [:]
        subscribed = []
        commands.linkDown()
        audioKey = nil
        if was {
            Log.event("board.down")
            onLinkDown?()
        }
    }

    private func ready(_ p: CBPeripheral) {
        connectDeadline?.cancel()
        stopScan()
        transportReady = true
        connecting = false
        lastError = ""
        pairedID = p.identifier
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.pairedKey)
        commands.linkUp()
        startWatchdog()
        Task { await authenticate(p) }
    }

    /// Prove to the stick that this is the owner's app (firmware 0.3.0+): pair a secret the first time (the user
    /// confirms the code on the stick), then answer its challenge and tag every following command.
    /// The stick answers nothing while it asks the user something (up to 60 s), e.g. a pairing code that an
    /// earlier launch of the app sent; keep asking for the status until it is free.
    private func statusWhenFree() async throws -> String {
        var attempt = 0
        while true {
            do { return try await commands.send(.status) } catch let e as BoardError where e.kind == .timeout && attempt < 13 {
                attempt += 1
                lastError = "Waiting for the stick to finish its question…"
            }
        }
    }

    private func authenticate(_ p: CBPeripheral) async {
        let id = p.identifier
        do {
            let status = BoardStatus.decode(try await statusWhenFree())
            if let state = status?.auth {
                var secret = SessionAuth.secret(for: id)
                if state == "none" || secret == nil {
                    let fresh = SessionAuth.newSecret()
                    pairingCode = SessionAuth.code(fresh)
                    Log.event("board.pair_secret", ["code": pairingCode ?? ""])
                    defer { pairingCode = nil }
                    // Saved first: if this app is closed while the stick asks, a later A still matches what we keep.
                    SessionAuth.store(fresh, for: id)
                    try await commands.send(.secret(SessionAuth.hex(fresh)))
                    secret = fresh
                }
                guard let secret, let nonce = SessionAuth.unhex(try await commands.send(.hello)) else {
                    throw BoardError(kind: .refused, message: "The stick sent no challenge.")
                }
                try await commands.send(.auth(SessionAuth.answer(secret: secret, nonce: nonce)))
                commands.signer = { SessionAuth.sign($0, secret: secret, nonce: nonce) }
                audioKey = SessionAuth.audioKey(secret: secret, nonce: nonce)
                if UserDefaults.standard.bool(forKey: "authSelfTest") {  // launch with -authSelfTest YES
                    let signer = commands.signer
                    commands.signer = nil
                    let unsigned = await Result(catching: { try await commands.send(.park) })
                    commands.signer = signer
                    let signed = await Result(catching: { try await commands.send(.park) })
                    Log.event("auth.selftest", ["unsigned_refused": (try? unsigned.get()) == nil,
                                                "signed_ok": (try? signed.get()) != nil])
                }
            }
            guard transportReady, p === peripheral else { return }
            connected = true
            lastError = ""
            Log.event("board.up", ["name": name, "mtu": p.maximumWriteValueLength(for: .withoutResponse) + 3,
                                   "auth": status?.auth != nil])
            onLinkUp?()
        } catch {
            let text = error.localizedDescription
            lastError = text.contains("locked") || text.contains("auth failed")
                ? "This stick is paired with another copy of Mantiza. Hold A and B together on the stick for 3 s, then tap Re-pair."
                : text
            Log.event("board.auth_failed", ["error": text])
        }
    }
}

extension BoardLink: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            bluetooth = central.state
            if central.state == .poweredOn { reconnect() } else { stopScan(); setDisconnected() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            if let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
                peripheral = restored
                restored.delegate = self
                Log.info("BLE restored link after relaunch")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                                    advertisementData: [String: Any], rssi: NSNumber) {
        MainActor.assumeIsolated {
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? "Mantiza Hands"
            discovered(p, name: name, rssi: rssi.intValue)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        MainActor.assumeIsolated {
            guard p === peripheral else { return }
            name = p.name ?? name
            p.discoverServices([BoardUUID.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            guard p === peripheral else { return }
            fail(error?.localizedDescription ?? "Could not connect to the stick.")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            guard p === peripheral else { return }
            setDisconnected()
            if let error { lastError = error.localizedDescription }
            retry?.cancel()
            retry = Task { [weak self] in
                guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
                self?.reconnect()
            }
        }
    }
}

extension BoardLink: CBPeripheralDelegate {
    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard p === peripheral else { return }
            if let error { return fail(error.localizedDescription) }
            guard let service = p.services?.first(where: { $0.uuid == BoardUUID.service }) else {
                return fail("This stick has no Mantiza service. Flash the Mantiza Hands firmware.")
            }
            p.discoverCharacteristics(BoardUUID.discover, for: service)
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard p === peripheral else { return }
            if let error { return fail(error.localizedDescription) }
            let available = Set((service.characteristics ?? []).map(\.uuid))
            guard available.isSuperset(of: BoardUUID.all) else {
                return fail("The stick firmware is too old. Update Mantiza Hands.")
            }
            for c in service.characteristics ?? [] {
                chars[c.uuid] = c
                if [BoardUUID.reply, BoardUUID.status, BoardUUID.audio].contains(c.uuid) { p.setNotifyValue(true, for: c) }
            }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard p === peripheral else { return }
            if let error { return fail("Subscribing failed: \(error.localizedDescription)") }
            guard c.isNotifying else { return }
            subscribed.insert(c.uuid)
            // Reading the encrypted status triggers pairing; the first answer marks the link ready.
            if !transportReady, subscribed.isSuperset(of: [BoardUUID.reply, BoardUUID.status]),
               let status = chars[BoardUUID.status] { p.readValue(for: status) }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard p === peripheral, error == nil, let value = c.value else { return }
            lastNotify = Date()
            switch c.uuid {
            case BoardUUID.reply:
                commands.handle(String(decoding: value, as: UTF8.self))
            case BoardUUID.audio:
                onAudio?(value)
            case BoardUUID.status:
                guard let s = BoardStatus.decode(value) else { return }
                if !transportReady, subscribed.isSuperset(of: [BoardUUID.reply, BoardUUID.status]) { ready(p) }
                let before = status?.inputReady
                status = status?.merged(with: s) ?? s
                if before != status?.inputReady { Log.event("board.hid", ["state": status?.hid ?? "?"]) }
            default: break
            }
        }
    }
}

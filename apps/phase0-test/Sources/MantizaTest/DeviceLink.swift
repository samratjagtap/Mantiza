import CoreBluetooth
import SwiftUI
import UIKit

/// IDs of the T2 command channel. Must match firmware/t1-hid-test/src/main.cpp.
enum MantizaID {
    static let service = CBUUID(string: "f665cd1c-b15f-4ffa-b950-9d0f007b7db5")
    static let write   = CBUUID(string: "2af74626-d331-4239-bd47-2ef715cab51e")  // app -> device
    static let event   = CBUUID(string: "7a537076-9f59-4e6d-94eb-c90356cea6f3")  // device -> app
    static let hid     = CBUUID(string: "1812")
    static let battery = CBUUID(string: "180F")
}

struct LogLine: Identifiable {
    let id = UUID()
    let time: Date
    let text: String
}

/// Talks to the Mantiza device over its command channel, while iOS keeps using the
/// same device as a Bluetooth mouse + keyboard (test T2).
@MainActor
final class DeviceLink: NSObject, ObservableObject {
    @Published var bluetooth = "Starting…"
    @Published var status = "Not connected"
    @Published var foundBy = "–"
    @Published var ready = false
    @Published var log: [LogLine] = []

    @Published var pingResult = "–"
    @Published var asksAnswered = 0
    @Published var asksInBackground = 0
    @Published var beatsSent = 0
    @Published var beating = false

    private var central: CBCentralManager!
    private var device: CBPeripheral?
    private var writeChar: CBCharacteristic?

    private var pingSentAt: [Int: Date] = [:]
    private var pingTimes: [Double] = []
    private var pingNumber = 0
    private var beatTask: Task<Void, Never>?

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self, queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "mantiza-test-central"])
    }

    // MARK: - Log

    func note(_ text: String) {
        log.insert(LogLine(time: Date(), text: text), at: 0)
        if log.count > 400 { log.removeLast() }
        print("[MantizaTest] \(text)")
    }

    private var inBackground: Bool { UIApplication.shared.applicationState == .background }

    // MARK: - Find the device

    /// The device is already connected to iOS as a mouse, so it doesn't advertise.
    /// Ask iOS for devices it is already connected to, trying several services.
    func findDevice() {
        guard central.state == .poweredOn else {
            note("Bluetooth is not on yet")
            return
        }
        if let d = device, d.state == .connected {
            if !ready { d.discoverServices([MantizaID.service]) }
            return
        }
        let searches: [(String, CBUUID)] = [
            ("Mantiza service", MantizaID.service),
            ("HID service", MantizaID.hid),
            ("Battery service", MantizaID.battery),
        ]
        for (label, uuid) in searches {
            let found = central.retrieveConnectedPeripherals(withServices: [uuid])
            note("Already-connected devices with \(label): \(found.count) \(found.map { $0.name ?? "?" })")
            if let d = found.first(where: { ($0.name ?? "").hasPrefix("Mantiza") }) {
                foundBy = "Already connected (\(label))"
                use(d)
                return
            }
        }
        note("Not in the connected list, scanning…")
        foundBy = "Scan"
        status = "Scanning…"
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    private func use(_ d: CBPeripheral) {
        central.stopScan()
        device = d
        d.delegate = self
        status = "Connecting…"
        note("Connecting to \(d.name ?? "?")")
        central.connect(d, options: nil)
    }

    // MARK: - Send

    func send(_ text: String) {
        guard let d = device, let c = writeChar, ready else {
            note("Can't send \"\(text)\": not ready")
            return
        }
        d.writeValue(Data(text.utf8), for: c, type: .withResponse)
    }

    func pingTen() {
        pingTimes = []
        pingResult = "running…"
        Task {
            for _ in 0..<10 {
                pingNumber += 1
                pingSentAt[pingNumber] = Date()
                send("ping \(pingNumber)")
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func moveSquare() {
        Task {
            for step in ["m 200 0", "m 0 200", "m -200 0", "m 0 -200"] {
                send(step)
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    func toggleBeat() {
        if let t = beatTask {
            t.cancel()
            beatTask = nil
            beating = false
            note("Heartbeat stopped after \(beatsSent)")
            return
        }
        beating = true
        beatsSent = 0
        beatTask = Task {
            while !Task.isCancelled {
                beatsSent += 1
                send("beat \(beatsSent)")
                note("beat \(beatsSent) sent\(inBackground ? " (background)" : "")")
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func resetCounts() {
        asksAnswered = 0
        asksInBackground = 0
        log.removeAll()
    }

    // MARK: - Receive

    private func handle(event text: String) {
        let parts = text.split(separator: " ")
        let number = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        switch parts.first {
        case "pong":
            if let sent = pingSentAt.removeValue(forKey: number) {
                let ms = Date().timeIntervalSince(sent) * 1000
                pingTimes.append(ms)
                let avg = pingTimes.reduce(0, +) / Double(pingTimes.count)
                pingResult = String(format: "%d/10 back · avg %.0f ms · max %.0f ms",
                                    pingTimes.count, avg, pingTimes.max() ?? 0)
            }
        case "ask":
            send("ack \(number)")
            asksAnswered += 1
            if inBackground { asksInBackground += 1 }
            note("ask \(number) answered\(inBackground ? " in the BACKGROUND" : "")")
        default:
            note("device: \(text)")
        }
    }
}

// MARK: - CoreBluetooth callbacks (delivered on the main queue)

extension DeviceLink: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetooth = "On"
        case .poweredOff: bluetooth = "Off"
        case .unauthorized: bluetooth = "Not allowed (Settings → Mantiza Test → Bluetooth)"
        case .unsupported: bluetooth = "Unsupported"
        default: bluetooth = "Unknown"
        }
        note("Bluetooth: \(bluetooth)")
        if central.state == .poweredOn { findDevice() }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
            device = restored
            restored.delegate = self
            note("iOS relaunched the app in the background (restored \(restored.name ?? "?"))")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        if name.hasPrefix("Mantiza") {
            note("Found \(name) by scanning")
            use(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Connected, looking for the command channel…"
        note("Connected")
        peripheral.discoverServices([MantizaID.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = "Connect failed"
        note("Connect failed: \(error?.localizedDescription ?? "?")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        ready = false
        writeChar = nil
        status = "Disconnected"
        note("Disconnected: \(error?.localizedDescription ?? "no error")")
        Task {
            try? await Task.sleep(for: .seconds(2))
            findDevice()
        }
    }
}

extension DeviceLink: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == MantizaID.service }) else {
            status = "Command channel not found"
            note("Command channel not found (services: \(peripheral.services?.map(\.uuid.uuidString) ?? []))")
            return
        }
        peripheral.discoverCharacteristics([MantizaID.write, MantizaID.event], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == MantizaID.write { writeChar = c }
            if c.uuid == MantizaID.event { peripheral.setNotifyValue(true, for: c) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            status = "Listen failed"
            note("Listen failed: \(error.localizedDescription)")
            return
        }
        ready = characteristic.isNotifying && writeChar != nil
        status = ready ? "Ready ✅" : "Not listening"
        note(ready ? "Command channel ready" : "Not listening")
        if ready { send("hello") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == MantizaID.event, let data = characteristic.value else { return }
        handle(event: String(decoding: data, as: UTF8.self))
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { note("Send failed: \(error.localizedDescription)") }
    }
}

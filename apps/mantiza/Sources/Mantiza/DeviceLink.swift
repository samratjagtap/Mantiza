import CoreBluetooth
import SwiftUI
import UIKit

/// IDs of the device's command channel. Must match the firmware (firmware/t1-hid-test/src/main.cpp).
enum DeviceID {
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

/// Talks to the Mantiza device over its command channel while iOS uses the same device as its
/// Bluetooth mouse and keyboard (proven in test T2).
///
/// Every command from the app gets exactly one reply ("ok …", "error …", "unknown command: …" or
/// "not connected …"), and the device runs commands one after another, so `run` can wait for each
/// command to finish.
@MainActor
final class DeviceLink: NSObject, ObservableObject {
    @Published var bluetooth = "Starting…"
    @Published var status = "Not connected"
    @Published var ready = false
    @Published var battery = "–"
    @Published var log: [LogLine] = []

    /// Called when the device sends "share" (its own menu item 4 asks the app to start sharing).
    var onShare: (() -> Void)?

    private var central: CBCentralManager!
    private var device: CBPeripheral?
    private var writeChar: CBCharacteristic?

    private struct Waiting { let id: Int; let continuation: CheckedContinuation<String, Never> }
    private var waiting: [Waiting] = []
    private var nextID = 0
    private var lateReplies = 0  // replies still owed to commands that timed out

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "mantiza-central"])
    }

    func note(_ text: String) {
        log.insert(LogLine(time: Date(), text: text), at: 0)
        if log.count > 500 { log.removeLast() }
        print("[Mantiza] \(text)")
    }

    // MARK: - Find the device

    /// The device is already connected to iOS as a mouse, so it doesn't advertise: ask iOS for
    /// devices it is already connected to, then fall back to scanning.
    func connect() {
        guard central.state == .poweredOn else { note("Bluetooth is not on yet"); return }
        if let d = device, d.state == .connected {
            if !ready { d.discoverServices([DeviceID.service]) }
            return
        }
        for uuid in [DeviceID.service, DeviceID.hid, DeviceID.battery] {
            if let d = central.retrieveConnectedPeripherals(withServices: [uuid])
                .first(where: { ($0.name ?? "").hasPrefix("Mantiza") }) {
                use(d)
                return
            }
        }
        status = "Looking for the device…"
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    private func use(_ d: CBPeripheral) {
        central.stopScan()
        device = d
        d.delegate = self
        status = "Connecting to \(d.name ?? "device")…"
        central.connect(d, options: nil)
    }

    // MARK: - Commands

    /// Sends a command without waiting.
    func send(_ text: String) {
        guard let d = device, let c = writeChar, ready else { note("Not sent (device not ready): \(text)"); return }
        d.writeValue(Data(text.utf8), for: c, type: .withResponse)
    }

    /// Sends a command and waits for the device's reply. Returns the reply, "timeout" or "not ready".
    @discardableResult
    func run(_ text: String, timeout: Double = 20) async -> String {
        guard ready else { note("Not sent (device not ready): \(text)"); return "not ready" }
        nextID += 1
        let id = nextID
        return await withCheckedContinuation { continuation in
            waiting.append(Waiting(id: id, continuation: continuation))
            send(text)
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if let i = waiting.firstIndex(where: { $0.id == id }) {
                    waiting.remove(at: i).continuation.resume(returning: "timeout")
                    lateReplies += 1
                    note("No reply to \"\(text)\" within \(Int(timeout)) s")
                }
            }
        }
    }

    // MARK: - Receive

    private func handle(event text: String) {
        let isReply = text.hasPrefix("ok ") || text.hasPrefix("error") || text.hasPrefix("unknown command")
            || text.hasPrefix("not connected")
        if isReply {
            if lateReplies > 0 { lateReplies -= 1; return }
            if !waiting.isEmpty { waiting.removeFirst().continuation.resume(returning: text) }
            if !text.hasPrefix("ok ") { note("device: \(text)") }
            return
        }
        let parts = text.split(separator: " ")
        switch parts.first {
        case "hi":
            if let i = parts.firstIndex(of: "battery"), i + 1 < parts.count { battery = String(parts[i + 1]) }
            note("device: \(text)")
        case "share":
            onShare?()
        default:
            note("device: \(text)")
        }
    }

    private func failAllWaiting() {
        for w in waiting { w.continuation.resume(returning: "not ready") }
        waiting.removeAll()
        lateReplies = 0
    }
}

// MARK: - CoreBluetooth callbacks (delivered on the main queue)

extension DeviceLink: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetooth = "On"
        case .poweredOff: bluetooth = "Off"
        case .unauthorized: bluetooth = "Not allowed (Settings → Mantiza → Bluetooth)"
        default: bluetooth = "Unavailable"
        }
        if central.state == .poweredOn { connect() }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
            device = restored
            restored.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        if name.hasPrefix("Mantiza") { use(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Connected, opening the command channel…"
        peripheral.discoverServices([DeviceID.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = "Connect failed"
        note("Connect failed: \(error?.localizedDescription ?? "?")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        ready = false
        writeChar = nil
        status = "Disconnected"
        failAllWaiting()
        note("Device disconnected")
        Task {
            try? await Task.sleep(for: .seconds(2))
            connect()
        }
    }
}

extension DeviceLink: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == DeviceID.service }) else {
            status = "Command channel not found (old firmware?)"
            return
        }
        peripheral.discoverCharacteristics([DeviceID.write, DeviceID.event], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == DeviceID.write { writeChar = c }
            if c.uuid == DeviceID.event { peripheral.setNotifyValue(true, for: c) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        ready = error == nil && characteristic.isNotifying && writeChar != nil
        status = ready ? "Ready ✅" : "Not listening"
        if ready {
            note("Device ready: \(peripheral.name ?? "?")")
            send("hello")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == DeviceID.event, let data = characteristic.value else { return }
        handle(event: String(decoding: data, as: UTF8.self))
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { note("Send failed: \(error.localizedDescription)") }
    }
}

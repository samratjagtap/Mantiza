import SwiftUI
import UIKit

/// T9: battery drain of the device and of the phone.
/// The device sends "batt <percent> <millivolts> <minutes> <charging>" every minute
/// (StickS3 menu "9 Battery test"). Each message also records the phone's battery and
/// whether screen capture is running, so both drains can be compared.
@MainActor
final class BatteryTest: ObservableObject {
    struct Sample: Codable, Identifiable {
        var id: Date { time }
        let time: Date
        let devicePct: Int
        let deviceMV: Int
        let deviceCharging: Bool
        let phonePct: Int        // -1 = unknown
        let phoneCharging: Bool
        let capturing: Bool
        let appInBackground: Bool
    }

    weak var capture: ScreenCapture?
    @Published var samples: [Sample] = []

    private let key = "t9.samples"

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Sample].self, from: data) {
            samples = saved
        }
    }

    /// Called for every "batt …" message from the device.
    func got(_ parts: [Substring]) {
        guard parts.count >= 5, let pct = Int(parts[1]), let mv = Int(parts[2]) else { return }
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        samples.append(Sample(
            time: Date(), devicePct: pct, deviceMV: mv, deviceCharging: parts[4] == "1",
            phonePct: level < 0 ? -1 : Int((level * 100).rounded()),
            phoneCharging: state == .charging || state == .full,
            capturing: capture?.running ?? false,
            appInBackground: UIApplication.shared.applicationState == .background))
        if samples.count > 3000 { samples.removeFirst() }
        save()
    }

    func clear() {
        samples.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(samples) { UserDefaults.standard.set(data, forKey: key) }
    }

    // MARK: - Summary

    var hours: Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.time.timeIntervalSince(first.time) / 3600
    }

    /// Percent per hour, from first to last sample (nil until there is half an hour of data).
    func rate(_ value: (Sample) -> Int) -> Double? {
        guard hours >= 0.5, let first = samples.first, let last = samples.last,
              value(first) >= 0, value(last) >= 0 else { return nil }
        return Double(value(first) - value(last)) / hours
    }

    var deviceRate: Double? { rate { $0.devicePct } }
    var phoneRate: Double? { rate { $0.phonePct } }
    var anyCharging: Bool { samples.contains { $0.deviceCharging || $0.phoneCharging } }
    var captureShare: Double {
        samples.isEmpty ? 0 : Double(samples.filter(\.capturing).count) / Double(samples.count)
    }
}

struct BatteryView: View {
    @EnvironmentObject var battery: BatteryTest

    private func rateText(_ rate: Double?, now: Int?) -> String {
        guard let rate else { return "needs 30+ min of data" }
        guard rate > 0.05 else { return "no drop yet" }
        var text = String(format: "%.1f %%/h", rate)
        if let now, now > 0 { text += String(format: " · ~%.0f h left", Double(now) / rate) }
        return text
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Samples", value: "\(battery.samples.count)")
                    LabeledContent("Running for", value: String(format: "%.1f h", battery.hours))
                    if let first = battery.samples.first, let last = battery.samples.last {
                        LabeledContent("Device", value: "\(first.devicePct)% → \(last.devicePct)% (\(last.deviceMV) mV)")
                        LabeledContent("Device drain", value: rateText(battery.deviceRate, now: last.devicePct))
                        LabeledContent("Phone", value: "\(first.phonePct)% → \(last.phonePct)%")
                        LabeledContent("Phone drain", value: rateText(battery.phoneRate, now: last.phonePct))
                        LabeledContent("Screen capture on", value: String(format: "%.0f%% of samples", battery.captureShare * 100))
                    }
                    if battery.anyCharging {
                        Text("⚠️ Something was charging during this run: the numbers are not valid. Unplug and start again.")
                            .foregroundStyle(.orange)
                    }
                    Button("Clear and start a new run", role: .destructive) { battery.clear() }
                } header: {
                    Text("T9 · Battery")
                } footer: {
                    Text("On the StickS3 pick \"9 Battery test\" and press the front button. Its screen turns off; the device reports every minute. Unplug the StickS3 from USB and the phone from the charger. Leave this app in the background. Saved samples survive an app restart.")
                }

                Section("Samples (newest first)") {
                    ForEach(battery.samples.reversed().prefix(200)) { s in
                        HStack {
                            Text(s.time, format: .dateTime.hour().minute())
                                .foregroundStyle(.secondary)
                            Text("dev \(s.devicePct)% \(s.deviceMV)mV")
                            Spacer()
                            Text("ph \(s.phonePct)%\(s.capturing ? " ●" : "")\(s.deviceCharging || s.phoneCharging ? " ⚡︎" : "")")
                        }
                        .font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Mantiza T9")
        }
    }
}

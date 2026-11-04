import Foundation
import CoreBluetooth
import SwiftUI

struct FoundDevice: Identifiable, Equatable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    static func == (a: FoundDevice, b: FoundDevice) -> Bool { a.id == b.id && a.rssi == b.rssi && a.name == b.name }
}

struct LogLine: Identifiable {
    let id = UUID()
    let time: Date
    let text: String
}

struct CharInfo: Identifiable {
    var id: String { service + "/" + uuid }
    let service: String
    let uuid: String
    let props: String
    let characteristic: CBCharacteristic
}

final class BLEManager: NSObject, ObservableObject {
    @Published var bluetoothOn = false
    @Published var scanning = false
    @Published var devices: [FoundDevice] = []
    @Published var connected: CBPeripheral?
    @Published var connectedName = ""
    @Published var chars: [CharInfo] = []
    @Published var log: [LogLine] = []

    @Published var heartRate: Int?
    @Published var battery: Int?
    @Published var hrHistory: [Int] = []
    var onHeartRate: ((Int) -> Void)?

    private var central: CBCentralManager!
    private let savedKey = "savedBandID"

    static let hrService = CBUUID(string: "180D")
    static let hrMeasure = CBUUID(string: "2A37")
    static let batService = CBUUID(string: "180F")
    static let batLevel = CBUUID(string: "2A19")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func addLog(_ s: String) {
        log.append(LogLine(time: Date(), text: s))
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
    }

    func startScan() {
        guard bluetoothOn else { return }
        devices.removeAll()
        scanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        addLog("Scanning...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.stopScan() }
    }

    func stopScan() {
        if scanning { central.stopScan(); scanning = false; addLog("Scan stopped") }
    }

    func connect(_ d: FoundDevice) {
        stopScan()
        connectedName = d.name
        central.connect(d.peripheral, options: nil)
        addLog("Connecting to \(d.name)...")
    }

    private var userDisconnected = false

    func disconnect() {
        userDisconnected = true
        if let p = connected { central.cancelPeripheralConnection(p) }
    }

    func forgetBand() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: savedKey)
    }

    func reconnectSaved() {
        guard let s = UserDefaults.standard.string(forKey: savedKey), let id = UUID(uuidString: s) else { return }
        let known = central.retrievePeripherals(withIdentifiers: [id])
        if let p = known.first {
            connectedName = p.name ?? "Band"
            central.connect(p, options: nil)
            addLog("Reconnecting to saved band...")
        }
        let already = central.retrieveConnectedPeripherals(withServices: [Self.hrService, Self.batService])
        for p in already where p.identifier == id {
            central.connect(p, options: nil)
        }
    }

    func read(_ c: CharInfo) {
        connected?.readValue(for: c.characteristic)
    }

    func write(_ c: CharInfo, hex: String) {
        guard let p = connected else { return }
        let clean = hex.replacingOccurrences(of: " ", with: "")
        var data = Data()
        var i = clean.startIndex
        while i < clean.endIndex {
            let j = clean.index(i, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
            if let b = UInt8(clean[i..<j], radix: 16) { data.append(b) } else { addLog("Bad hex: \(hex)"); return }
            i = j
        }
        let type: CBCharacteristicWriteType = c.characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(data, for: c.characteristic, type: type)
        addLog("WRITE \(short(c.uuid)) → \(hexString(data))")
    }

    func short(_ u: String) -> String { u.count > 8 ? String(u.prefix(8)) : u }

    func hexString(_ d: Data) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }

    func propsString(_ p: CBCharacteristicProperties) -> String {
        var a: [String] = []
        if p.contains(.read) { a.append("read") }
        if p.contains(.write) { a.append("write") }
        if p.contains(.writeWithoutResponse) { a.append("write-nr") }
        if p.contains(.notify) { a.append("notify") }
        if p.contains(.indicate) { a.append("indicate") }
        return a.joined(separator: ", ")
    }

    var logText: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        var s = "Band detective log — \(connectedName)\n\nCharacteristics:\n"
        for c in chars { s += "• svc \(c.service) / char \(c.uuid) [\(c.props)]\n" }
        s += "\nLog:\n"
        for l in log { s += "\(f.string(from: l.time))  \(l.text)\n" }
        return s
    }
}

extension BLEManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        bluetoothOn = c.state == .poweredOn
        addLog(bluetoothOn ? "Bluetooth is on" : "Bluetooth is off or not allowed")
        if bluetoothOn { reconnectSaved() }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        if name.isEmpty { return }
        if let i = devices.firstIndex(where: { $0.id == p.identifier }) {
            devices[i].rssi = rssi.intValue
        } else {
            devices.append(FoundDevice(id: p.identifier, peripheral: p, name: name, rssi: rssi.intValue))
            devices.sort { $0.rssi > $1.rssi }
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        connected = p
        if connectedName.isEmpty { connectedName = p.name ?? "Band" }
        UserDefaults.standard.set(p.identifier.uuidString, forKey: savedKey)
        p.delegate = self
        chars.removeAll()
        addLog("Connected to \(connectedName). Looking at its services...")
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        addLog("Could not connect: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        addLog("Disconnected")
        connected = nil
        if !userDisconnected {
            addLog("Will reconnect when the band is near")
            central.connect(p, options: nil)
        }
        userDisconnected = false
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            addLog("Service \(s.uuid.uuidString)")
            p.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            let info = CharInfo(service: s.uuid.uuidString, uuid: ch.uuid.uuidString, props: propsString(ch.properties), characteristic: ch)
            chars.append(info)
            addLog("  char \(ch.uuid.uuidString) [\(info.props)]")
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                p.setNotifyValue(true, for: ch)
            }
            if ch.properties.contains(.read) {
                p.readValue(for: ch)
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value else { return }
        if ch.uuid == Self.hrMeasure, d.count >= 2 {
            let flags = d[0]
            let bpm = (flags & 0x01) == 0 ? Int(d[1]) : (d.count >= 3 ? Int(d[1]) | (Int(d[2]) << 8) : Int(d[1]))
            if bpm > 0 {
                heartRate = bpm
                onHeartRate?(bpm)
                hrHistory.append(bpm)
                if hrHistory.count > 120 { hrHistory.removeFirst() }
            }
        }
        if ch.uuid == Self.batLevel, let b = d.first {
            battery = Int(b)
        }
        let ascii = String(data: d, encoding: .utf8).map { $0.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value < 127 } ? "  \"\($0)\"" : "" } ?? ""
        addLog("◀ \(short(ch.uuid.uuidString)): \(hexString(d))\(ascii)")
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let e = error { addLog("  notify fail \(short(ch.uuid.uuidString)): \(e.localizedDescription)") }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let e = error { addLog("  write fail: \(e.localizedDescription)") }
    }
}

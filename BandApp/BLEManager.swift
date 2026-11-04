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

    // WP band (Podsfine) protocol
    @Published var isWPBand = false
    @Published var steps: Int?
    @Published var hrMeasuring = false
    @Published var bpMeasuring = false
    @Published var lastBandHR: Int?
    @Published var lastBandBP: (sys: Int, dia: Int)?
    var onHRResult: ((Int) -> Void)?
    var onBPResult: ((Int, Int) -> Void)?
    var onSteps: ((Int) -> Void)?
    var buzzSeq = 0
    var txQueue: [WPOut] = []
    var txWaiting: (UInt8, UInt8)?
    var txSeq = 0
    var wpWrite: CBCharacteristic?
    var wpNotify: CBCharacteristic?
    var rx: [UInt8] = []
    static let wpWriteUUID = CBUUID(string: "2AAD")
    static let wpNotifyUUID = CBUUID(string: "2AAC")

    private var central: CBCentralManager!
    /// iOS cancels a connection if the app doesn't hold on to the band object, so keep it here.
    private var keep: CBPeripheral?
    private let savedKey = "savedBandID"

    static let hrService = CBUUID(string: "180D")
    static let hrMeasure = CBUUID(string: "2A37")
    static let batService = CBUUID(string: "180F")
    static let batLevel = CBUUID(string: "2A19")

    override init() {
        super.init()
        // The restore key lets iOS wake the app for the band after it was paused in the background.
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "band-central"])
    }

    func addLog(_ s: String) {
        log.append(LogLine(time: Date(), text: s))
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
    }

    /// Services that cheap bands commonly use. A band that is already connected
    /// to the phone (through Podsfine) stays quiet, so we also ask iOS for
    /// connected devices that offer any of these.
    static let commonServices: [CBUUID] = [
        "180D", "180F", "180A", "1800", "1801", "1810", "1814", "1816", "181C", "181D",
        "FEE7", "FEE0", "FEE1", "FEA0", "FEEA", "FE59", "FFF0", "FFE0", "FFD0", "FFC0",
        "FF00", "FE00", "FD00", "AE00", "AE30", "190E", "3802", "D0FF", "FEF5", "FEBA",
        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E",
        "0000FEE7-0000-1000-8000-00805F9B34FB",
    ].map { CBUUID(string: $0) }

    func startScan() {
        guard bluetoothOn else { return }
        devices.removeAll()
        scanning = true
        addLog("Scanning...")

        let already = central.retrieveConnectedPeripherals(withServices: Self.commonServices)
        for p in already {
            let name = p.name ?? "Connected device"
            addLog("Already connected to phone: \(name)")
            devices.append(FoundDevice(id: p.identifier, peripheral: p, name: "\(name) · connected", rssi: 0))
        }

        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.stopScan() }
    }

    func stopScan() {
        if scanning { central.stopScan(); scanning = false; addLog("Scan stopped") }
    }

    func connect(_ d: FoundDevice) {
        stopScan()
        keep = d.peripheral
        connectedName = d.name.replacingOccurrences(of: " · connected", with: "")
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
            keep = p
            connectedName = p.name ?? "Band"
            central.connect(p, options: nil)
            addLog("Reconnecting to saved band...")
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
    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let list = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = list.first {
            keep = p
            p.delegate = self
            connectedName = p.name ?? "Band"
            if p.state == .connected {
                connected = p
                p.discoverServices(nil)
            }
            addLog("Restored band connection")
        }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        bluetoothOn = c.state == .poweredOn
        addLog(bluetoothOn ? "Bluetooth is on" : "Bluetooth is off or not allowed")
        if bluetoothOn { reconnectSaved() }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        var name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        let r = rssi.intValue
        if r == 127 { return }
        if name.isEmpty { name = "No name · " + String(p.identifier.uuidString.prefix(4)) }
        if let i = devices.firstIndex(where: { $0.id == p.identifier }) {
            devices[i].rssi = r
        } else {
            devices.append(FoundDevice(id: p.identifier, peripheral: p, name: name, rssi: r))
            var extra = ""
            if let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data { extra += " mfr=\(hexString(m))" }
            if let s = ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] { extra += " svc=\(s.map { $0.uuidString }.joined(separator: ","))" }
            addLog("Found \(name) \(r) dBm\(extra)")
        }
        devices.sort { ($0.rssi == 0 ? 1 : 0, $0.rssi) > ($1.rssi == 0 ? 1 : 0, $1.rssi) }
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
        isWPBand = false
        wpResetQueue()
        wpWrite = nil
        wpNotify = nil
        rx = []
        hrMeasuring = false
        bpMeasuring = false
        if !userDisconnected {
            addLog("Will reconnect when the band is near")
            keep = p
            central.connect(p, options: nil)
        } else {
            keep = nil
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
            if ch.uuid == Self.wpWriteUUID { wpWrite = ch }
            if ch.uuid == Self.wpNotifyUUID { wpNotify = ch }
            if wpWrite != nil && wpNotify != nil && !isWPBand {
                isWPBand = true
                addLog("This is a WP band. Using its own language.")
            }
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
        if ch.uuid == Self.wpNotifyUUID {
            wpReceive([UInt8](d))
        }
        let ascii = String(data: d, encoding: .utf8).map { $0.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value < 127 } ? "  \"\($0)\"" : "" } ?? ""
        addLog("◀ \(short(ch.uuid.uuidString)): \(hexString(d))\(ascii)")
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let e = error { addLog("  notify fail \(short(ch.uuid.uuidString)): \(e.localizedDescription)") }
        if ch.uuid == Self.wpNotifyUUID && ch.isNotifying {
            wpStart()
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let e = error { addLog("  write fail: \(e.localizedDescription)") }
    }
}

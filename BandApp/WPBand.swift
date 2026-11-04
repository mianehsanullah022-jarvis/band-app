import Foundation
import CoreBluetooth

/// The WP band's own language, learned from a recording of the Podsfine app.
///
/// Every message is a frame:
///   [head][0x00][length][checksum][group][flag][id][0x00][dataLength][data…]
/// head 0xDF = a message, 0xFD = "got it" (an acknowledgement).
/// checksum = sum of every other byte in the frame, kept to one byte.
/// The phone writes frames to characteristic 2AAD; the band answers on 2AAC.
extension BLEManager {

    // MARK: Building and sending

    static func wpFrame(head: UInt8, group: UInt8, flag: UInt8, id: UInt8, data: [UInt8]) -> [UInt8] {
        let payload: [UInt8] = [group, flag, id, 0x00, UInt8(data.count)] + data
        let sum = Int(head) + payload.count + payload.reduce(0) { $0 + Int($1) }
        return [head, 0x00, UInt8(payload.count), UInt8(sum & 0xFF)] + payload
    }

    func wpSend(group: UInt8, flag: UInt8 = 0x04, id: UInt8, data: [UInt8], log: String? = nil) {
        guard let p = connected, let ch = wpWrite else {
            addLog("Band not ready yet")
            return
        }
        let frame = Self.wpFrame(head: 0xDF, group: group, flag: flag, id: id, data: data)
        p.writeValue(Data(frame), for: ch, type: .withoutResponse)
        addLog("▶ \(log ?? "send"): \(hexString(Data(frame)))")
    }

    private func wpAck(group: UInt8, id: UInt8) {
        guard let p = connected, let ch = wpWrite else { return }
        let frame = Self.wpFrame(head: 0xFD, group: group, flag: 0x04, id: id, data: [0x00])
        p.writeValue(Data(frame), for: ch, type: .withoutResponse)
    }

    // MARK: Commands (exact bytes Podsfine uses)

    /// Called once the band is ready to talk.
    func wpStart() {
        addLog("Talking to the band…")
        wpRefresh()
    }

    func wpRefresh() {
        wpSend(group: 0x11, id: 0x00, data: [0x01], log: "battery?")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.wpSend(group: 0x02, id: 0x12, data: [0x00, 0x00], log: "today?")
        }
    }

    func measureHeartRate() {
        hrMeasuring = true
        wpSend(group: 0x06, id: 0x04, data: [0x01], log: "measure heart rate")
        timeoutMeasuring()
    }

    func measureBloodPressure() {
        bpMeasuring = true
        wpSend(group: 0x06, id: 0x05, data: [0x01], log: "measure blood pressure")
        timeoutMeasuring()
    }

    /// Makes the band vibrate ("Find band" in Podsfine).
    func findBand() {
        wpSend(group: 0x06, flag: 0x01, id: 0x0F, data: [0x01], log: "find band")
    }

    /// Buzzes the band several times in a row.
    func buzz(times: Int, gap: Double = 2.5) {
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * gap) { [weak self] in self?.findBand() }
        }
    }

    private func timeoutMeasuring() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            self?.hrMeasuring = false
            self?.bpMeasuring = false
        }
    }

    // MARK: Receiving

    func wpReceive(_ bytes: [UInt8]) {
        rx += bytes
        while rx.count >= 4 {
            guard rx[0] == 0xDF || rx[0] == 0xFD else {
                rx.removeFirst()
                continue
            }
            let total = 4 + Int(rx[2])
            guard rx.count >= total else { return }   // wait for the rest
            let frame = Array(rx[0..<total])
            rx.removeFirst(total)
            wpHandle(frame)
        }
    }

    private func wpHandle(_ f: [UInt8]) {
        let p = Array(f[4...])
        guard p.count >= 5 else { return }
        let group = p[0], id = p[2]
        let len = Int(p[4])
        let data = Array(p.dropFirst(5).prefix(len))

        if f[0] == 0xFD { return }          // band saying "got it"
        wpAck(group: group, id: id)         // we say "got it" back, like Podsfine

        switch (group, id) {
        case (0x11, _) where data.count == 1:
            battery = Int(data[0])
            addLog("Battery \(data[0])%")

        case (0x03, 0x0F) where data.count == 1:
            hrMeasuring = data[0] == 1
            addLog(hrMeasuring ? "Band is measuring heart rate…" : "Heart rate measuring finished")

        case (0x03, 0x15) where data.count == 1:
            bpMeasuring = data[0] == 1
            addLog(bpMeasuring ? "Band is measuring blood pressure…" : "Blood pressure measuring finished")

        case (0x03, 0x00) where data.count >= 12:
            let hr = Int(data[11])
            hrMeasuring = false
            if hr > 0 {
                lastBandHR = hr
                heartRate = hr
                hrHistory.append(hr)
                if hrHistory.count > 120 { hrHistory.removeFirst() }
                onHeartRate?(hr)
                onHRResult?(hr)
                addLog("Heart rate result: \(hr) bpm")
            }

        case (0x03, 0x01) where data.count >= 12:
            let sys = Int(data[10]), dia = Int(data[11])
            bpMeasuring = false
            if sys > 0 && dia > 0 {
                lastBandBP = (sys, dia)
                onBPResult?(sys, dia)
                addLog("Blood pressure result: \(sys)/\(dia)")
            }

        case (0x04, 0x00) where data.count >= 4:
            let s = (Int(data[0]) << 24) | (Int(data[1]) << 16) | (Int(data[2]) << 8) | Int(data[3])
            steps = s
            addLog("Steps today: \(s)")

        default:
            break
        }
    }
}

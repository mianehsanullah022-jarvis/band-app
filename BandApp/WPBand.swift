import Foundation
import CoreBluetooth

/// A message waiting to be sent to the band.
struct WPOut {
    let group: UInt8
    let flag: UInt8
    let id: UInt8
    let data: [UInt8]
    let log: String
}

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

    /// Messages go one at a time: the band answers each one ("got it") after about
    /// a second, and Podsfine always waits for that answer before sending the next.
    func wpSend(group: UInt8, flag: UInt8 = 0x04, id: UInt8, data: [UInt8], log: String? = nil) {
        guard connected != nil, wpWrite != nil else {
            addLog("Band not ready yet")
            return
        }
        txQueue.append(WPOut(group: group, flag: flag, id: id, data: data, log: log ?? "send"))
        wpPump()
    }

    private func wpPump() {
        guard txWaiting == nil, !txQueue.isEmpty, let p = connected, let ch = wpWrite else { return }
        let m = txQueue.removeFirst()
        let frame = Self.wpFrame(head: 0xDF, group: m.group, flag: m.flag, id: m.id, data: m.data)
        p.writeValue(Data(frame), for: ch, type: .withoutResponse)
        addLog("▶ \(m.log): \(hexString(Data(frame)))")
        txWaiting = (m.group, m.id)
        txSeq += 1
        let n = txSeq
        // If the band doesn't answer within 2 seconds, move on anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, self.txSeq == n, self.txWaiting != nil else { return }
            self.txWaiting = nil
            self.wpPump()
        }
    }

    /// The band said "got it" to one of our messages.
    private func wpGotAck(group: UInt8, id: UInt8) {
        if let w = txWaiting, w.0 == group, w.1 == id {
            txWaiting = nil
            wpPump()
        }
    }

    func wpResetQueue() {
        txQueue.removeAll()
        txWaiting = nil
        txSeq += 1
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
        wpResetQueue()
        vibrateStop()      // if the band was left buzzing earlier, this quiets it
        wpRefresh()
    }

    func wpRefresh() {
        wpSend(group: 0x11, id: 0x00, data: [0x01], log: "battery?")
        wpSend(group: 0x02, id: 0x12, data: [0x00, 0x00], log: "today?")
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

    // Vibration, exactly as Podsfine's "Find device" does it (from the recording):
    //   start: group 06, flag 04, id 00, data 01   → band buzzes and keeps buzzing
    //   stop:  group 06, flag 01, id 0F, data 01   → band stops
    // Podsfine never sends "data 00" for these, so neither do we.

    func vibrateStart() {
        wpSend(group: 0x06, flag: 0x04, id: 0x00, data: [0x01], log: "vibrate START")
    }

    func vibrateStop() {
        wpSend(group: 0x06, flag: 0x01, id: 0x0F, data: [0x01], log: "vibrate STOP")
    }

    /// "Find my band": buzz for 3 seconds, then stop.
    func findBand() {
        buzzOnce(seconds: 3)
    }

    /// One buzz: start, then stop after `seconds`. The band needs about a second
    /// per message, so buzzes shorter than 1 second aren't possible.
    func buzzOnce(seconds: Double = 1.0) {
        buzzSeq += 1
        let n = buzzSeq
        vibrateStart()
        DispatchQueue.main.asyncAfter(deadline: .now() + max(seconds, 1.0)) { [weak self] in
            guard let self = self, self.buzzSeq == n else { return }   // stopVibrate already stopped it
            self.vibrateStop()
        }
    }

    /// Stops the band now: drops anything waiting to be sent, then sends "stop"
    /// right away and once more a little later, in case the first one is missed.
    func stopVibrate() {
        buzzSeq += 1
        let n = buzzSeq
        wpResetQueue()
        vibrateStop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self = self, self.buzzSeq == n else { return }   // a new buzz started; it stops itself
            self.vibrateStop()
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

        if f[0] == 0xFD {                   // band saying "got it" to our message
            wpGotAck(group: group, id: id)
            return
        }
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
            onSteps?(s)
            addLog("Steps today: \(s)")

        default:
            break
        }
    }
}

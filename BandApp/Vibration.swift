import Foundation
import SwiftUI
import CallKit
import UserNotifications

// MARK: Patterns

/// A vibration pattern: the band buzzes once at each time (seconds from the start).
struct VibePattern: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let times: [Double]
    var buzz: Double = 0.5          // how long each buzz lasts, in seconds
    var length: Double { (times.last ?? 0) + buzz + 1.0 }
}

enum Vibes {
    static let all: [VibePattern] = [
        VibePattern(id: "single", name: "Single", symbol: "1.circle.fill", times: [0], buzz: 0.5),
        VibePattern(id: "double", name: "Double", symbol: "2.circle.fill", times: [0, 0.9], buzz: 0.45),
        VibePattern(id: "triple", name: "Triple", symbol: "3.circle.fill", times: [0, 0.8, 1.6], buzz: 0.4),
        VibePattern(id: "heartbeat", name: "Heartbeat", symbol: "heart.fill", times: [0, 0.6, 1.8, 2.4], buzz: 0.3),
        VibePattern(id: "knock", name: "Knock knock", symbol: "hand.raised.fill", times: [0, 0.7, 2.2], buzz: 0.35),
        VibePattern(id: "wave", name: "Wave", symbol: "water.waves", times: [0, 1.0, 2.2, 3.6, 5.2], buzz: 0.6),
        VibePattern(id: "rush", name: "Rush", symbol: "bolt.fill", times: [0, 0.5, 1.0, 1.5, 2.0, 2.5], buzz: 0.3),
        VibePattern(id: "sos", name: "SOS", symbol: "sos", times: [0, 0.6, 1.2, 2.2, 3.4, 4.6, 5.8, 6.4, 7.0], buzz: 0.3),
        VibePattern(id: "long", name: "Long", symbol: "minus.circle.fill", times: [0], buzz: 2.0),
        VibePattern(id: "gentle", name: "Gentle", symbol: "leaf.fill", times: [0, 3.0], buzz: 0.25),
        VibePattern(id: "call", name: "Call (non-stop)", symbol: "phone.fill", times: [0, 2.0], buzz: 1.5),
    ]

    static func find(_ id: String) -> VibePattern { all.first { $0.id == id } ?? all[0] }
}

// MARK: Player

/// Plays patterns on the band. A new pattern or stop() cancels the one playing.
final class VibePlayer: ObservableObject {
    @Published var playing: String?
    @Published var repeating = false
    private var generation = 0
    private weak var ble: BLEManager?

    func attach(_ ble: BLEManager) { self.ble = ble }

    func play(_ p: VibePattern) {
        generation += 1
        let g = generation
        playing = p.id
        repeating = false
        run(p, g) { [weak self] in
            if self?.generation == g { self?.playing = nil }
        }
    }

    /// Repeats a pattern until stop() is called (or the safety limit).
    func playUntilStopped(_ p: VibePattern, maxSeconds: Double = 120) {
        generation += 1
        let g = generation
        playing = p.id
        repeating = true
        let started = Date()
        func loop() {
            guard generation == g else { return }
            if Date().timeIntervalSince(started) > maxSeconds { stop(); return }
            run(p, g) { loop() }
        }
        loop()
    }

    func stop() {
        generation += 1
        playing = nil
        repeating = false
        ble?.stopVibrate()
    }

    private func run(_ p: VibePattern, _ g: Int, done: @escaping () -> Void) {
        for t in p.times {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self = self, self.generation == g else { return }
                self.ble?.buzzOnce(seconds: p.buzz)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + p.length) { done() }
    }
}

// MARK: Settings, alarms and reminders

struct BandAlarm: Codable, Identifiable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var label: String
    var enabled: Bool = true
    var lastFired: String? = nil

    var timeText: String { String(format: "%02d:%02d", hour, minute) }
}

struct VibeSettings: Codable {
    var callBuzz = true
    var alarms: [BandAlarm] = []
    var waterReminder = false
    var waterEveryMin = 60
    var waterPattern = "wave"
    var standReminder = false
    var standEveryMin = 60
    var standPattern = "knock"
    var quietFrom = 23
    var quietTo = 8
}

/// Watches calls, alarms and reminders and buzzes the band.
final class VibeCenter: NSObject, ObservableObject, CXCallObserverDelegate, UNUserNotificationCenterDelegate {
    @Published var settings = VibeSettings() { didSet { save() } }
    @Published var alert: String?          // shown on screen with a Stop button
    @Published var callRinging = false

    let player = VibePlayer()
    private let callObserver = CXCallObserver()
    private var timer: Timer?
    private var lastWater = Date()
    private var lastStand = Date()
    private let key = "vibeSettings"

    override init() {
        super.init()
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(VibeSettings.self, from: d) {
            settings = s
        }
        callObserver.setDelegate(self, queue: .main)
        let stop = UNNotificationAction(identifier: "STOP", title: "Stop", options: [.destructive])
        let cat = UNNotificationCategory(identifier: "BAND_ALARM", actions: [stop], intentIdentifiers: [],
                                         options: [.customDismissAction])
        let nc = UNUserNotificationCenter.current()
        nc.setNotificationCategories([cat])
        nc.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
    }

    func attach(_ ble: BLEManager) { player.attach(ble) }

    func save() {
        if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: key) }
        scheduleBackupNotifications()
    }

    func stopAll() {
        player.stop()
        alert = nil
    }

    // Any action on our alarm notification (tap, Stop, or swipe away) stops the band.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        DispatchQueue.main.async { self.stopAll() }
        done()
    }

    // If the alarm notification arrives while Band is open, the app shows its own Stop screen.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([])
    }

    // Calls: buzz non-stop while an incoming call is ringing.
    func callObserver(_ o: CXCallObserver, callChanged call: CXCall) {
        let ringing = !call.isOutgoing && !call.hasConnected && !call.hasEnded
        if ringing && settings.callBuzz && !callRinging {
            callRinging = true
            alert = "Incoming call"
            player.playUntilStopped(Vibes.find("call"), maxSeconds: 90)
        } else if !ringing && callRinging {
            callRinging = false
            stopAll()
        }
    }

    // Alarms and reminders, checked every 10 seconds.
    private func tick() {
        let now = Date()
        let cal = Calendar.current
        let h = cal.component(.hour, from: now), m = cal.component(.minute, from: now)
        let today = Store.dayKey(now)

        for i in settings.alarms.indices where settings.alarms[i].enabled {
            let a = settings.alarms[i]
            if a.hour == h && a.minute == m && a.lastFired != today {
                settings.alarms[i].lastFired = today
                alert = a.label.isEmpty ? "Alarm \(a.timeText)" : a.label
                player.playUntilStopped(Vibes.find("call"), maxSeconds: 60)
                return
            }
        }

        guard player.playing == nil, !isQuiet(h) else { return }
        if settings.waterReminder, now.timeIntervalSince(lastWater) >= Double(settings.waterEveryMin * 60) {
            lastWater = now
            player.play(Vibes.find(settings.waterPattern))
        } else if settings.standReminder, now.timeIntervalSince(lastStand) >= Double(settings.standEveryMin * 60) {
            lastStand = now
            player.play(Vibes.find(settings.standPattern))
        }
    }

    private func isQuiet(_ h: Int) -> Bool {
        let a = settings.quietFrom, b = settings.quietTo
        return a <= b ? (h >= a && h < b) : (h >= a || h < b)
    }

    /// Phone notifications for alarms, so you still get alerted if iOS paused the app.
    func scheduleBackupNotifications() {
        let c = UNUserNotificationCenter.current()
        c.removeAllPendingNotificationRequests()
        for a in settings.alarms where a.enabled {
            let content = UNMutableNotificationContent()
            content.title = a.label.isEmpty ? "Alarm" : a.label
            content.body = "Tap Stop, open, or swipe away to stop the band."
            content.sound = .default
            content.categoryIdentifier = "BAND_ALARM"
            var dc = DateComponents()
            dc.hour = a.hour
            dc.minute = a.minute
            let req = UNNotificationRequest(identifier: a.id.uuidString,
                                            content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true))
            c.add(req)
        }
    }

    func askNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

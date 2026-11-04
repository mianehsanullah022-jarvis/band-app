import Foundation
import SwiftUI

struct HRSample: Codable {
    let t: Date
    let bpm: Int
}

struct Workout: Codable, Identifiable {
    var id = UUID()
    var type: String
    var start: Date
    var end: Date
    var avgHR: Int
    var maxHR: Int
    var calories: Int
    var strain: Double
    var zoneSeconds: [Double]
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct Profile: Codable {
    var name: String = ""
    var age: Int = 29
    var weightKg: Double = 70
    var male: Bool = true
    var maxHR: Int { Int(208 - 0.7 * Double(age)) }
}

/// Saves heart-rate history, workouts and the profile on the phone,
/// and turns heart rate into estimates (strain, calories, zones).
final class Store: ObservableObject {
    @Published var profile = Profile() { didSet { save() } }
    @Published var samples: [HRSample] = []
    @Published var workouts: [Workout] = []

    // Live workout
    @Published var activeType: String?
    @Published var activeStart: Date?
    @Published var activeSamples: [HRSample] = []

    private var lastSampleTime = Date.distantPast
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("band-data.json")
    }()

    private struct Saved: Codable {
        var profile: Profile
        var samples: [HRSample]
        var workouts: [Workout]
    }

    init() { load() }

    func load() {
        guard let d = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(Saved.self, from: d) else { return }
        samples = s.samples
        workouts = s.workouts
        profile = s.profile
        trim()
    }

    func save() {
        let s = Saved(profile: profile, samples: samples, workouts: workouts)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: fileURL, options: .atomic) }
    }

    func trim() {
        let cutoff = Date().addingTimeInterval(-14 * 86400)
        samples.removeAll { $0.t < cutoff }
    }

    func resetAll() {
        samples = []
        workouts = []
        save()
    }

    /// Called every time the band sends a heart-rate value.
    func addHR(_ bpm: Int) {
        guard bpm >= 30, bpm <= 230 else { return }
        let now = Date()
        if activeStart != nil { activeSamples.append(HRSample(t: now, bpm: bpm)) }
        if now.timeIntervalSince(lastSampleTime) >= 5 {
            lastSampleTime = now
            samples.append(HRSample(t: now, bpm: bpm))
            if samples.count % 60 == 0 { trim(); save() }
        }
    }

    // MARK: Today

    var today: [HRSample] {
        let start = Calendar.current.startOfDay(for: Date())
        return samples.filter { $0.t >= start }
    }

    var todayWorkouts: [Workout] {
        let start = Calendar.current.startOfDay(for: Date())
        return workouts.filter { $0.start >= start }.sorted { $0.start > $1.start }
    }

    /// Lowest steady heart rate seen in the last 2 days (an estimate of resting HR).
    var restingHR: Int? {
        let recent = samples.filter { $0.t > Date().addingTimeInterval(-2 * 86400) }.map { $0.bpm }.sorted()
        guard recent.count >= 20 else { return nil }
        return recent[recent.count / 20]
    }

    var todayStrain: Double? {
        let s = today
        guard s.count >= 10 else { return nil }
        return Self.strain(trimp: trimp(s))
    }

    var todayCalories: Int? {
        let s = today
        guard s.count >= 10 else { return nil }
        return Int(calories(s))
    }

    var todayZones: [Double] { zones(today) }

    // MARK: Math

    func zone(for bpm: Int) -> Int {
        let p = Double(bpm) / Double(profile.maxHR)
        switch p {
        case ..<0.5: return 0
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }

    /// Seconds spent in zones 1...5 (index 0 = zone 1).
    func zones(_ s: [HRSample]) -> [Double] {
        var z = [Double](repeating: 0, count: 5)
        for (a, b) in zip(s, s.dropFirst()) {
            let dt = min(b.t.timeIntervalSince(a.t), 60)
            let zi = zone(for: a.bpm)
            if zi >= 1 { z[zi - 1] += dt }
        }
        return z
    }

    /// Banister training impulse from heart rate.
    func trimp(_ s: [HRSample]) -> Double {
        let rest = Double(restingHR ?? 60)
        let maxH = Double(profile.maxHR)
        let k = profile.male ? 1.92 : 1.67
        var total = 0.0
        for (a, b) in zip(s, s.dropFirst()) {
            let minutes = min(b.t.timeIntervalSince(a.t), 60) / 60
            let hrr = max(0, min(1, (Double(a.bpm) - rest) / max(maxH - rest, 1)))
            total += minutes * hrr * 0.64 * exp(k * hrr)
        }
        return total
    }

    /// Maps training load to a 0–21 scale.
    static func strain(trimp: Double) -> Double {
        let v = 21 * (1 - exp(-trimp / 90))
        return (v * 10).rounded() / 10
    }

    /// Keytel et al. (2005) heart-rate calorie estimate.
    func calories(_ s: [HRSample]) -> Double {
        let w = profile.weightKg, a = Double(profile.age)
        var kcal = 0.0
        for (x, y) in zip(s, s.dropFirst()) {
            let minutes = min(y.t.timeIntervalSince(x.t), 60) / 60
            let hr = Double(x.bpm)
            let perMin = profile.male
                ? (-55.0969 + 0.6309 * hr + 0.1988 * w + 0.2017 * a) / 4.184
                : (-20.4022 + 0.4472 * hr - 0.1263 * w + 0.074 * a) / 4.184
            kcal += max(perMin, 1.0) * minutes
        }
        return kcal
    }

    // MARK: Workouts

    func startWorkout(_ type: String) {
        activeType = type
        activeStart = Date()
        activeSamples = []
    }

    func stopWorkout() {
        guard let type = activeType, let start = activeStart else { return }
        let s = activeSamples
        let bpms = s.map { $0.bpm }
        let w = Workout(
            type: type, start: start, end: Date(),
            avgHR: bpms.isEmpty ? 0 : bpms.reduce(0, +) / bpms.count,
            maxHR: bpms.max() ?? 0,
            calories: Int(calories(s)),
            strain: Self.strain(trimp: trimp(s)),
            zoneSeconds: zones(s))
        if w.duration > 30 { workouts.append(w); save() }
        activeType = nil
        activeStart = nil
        activeSamples = []
    }
}

func fmtDuration(_ t: TimeInterval) -> String {
    let s = Int(t)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

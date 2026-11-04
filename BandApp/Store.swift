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

struct BPReading: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var systolic: Int
    var diastolic: Int
    var pulse: Int?
    var fromBand: Bool? = nil
}

struct HRCheck: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var bpm: Int
    var low: Int
    var high: Int
}

struct WaterBar: Identifiable {
    var id: Int { index }
    let index: Int
    let label: String
    let ml: Int
}

struct WaterDay: Codable {
    var day: String
    var ml: Int
}

struct Profile: Codable {
    var name: String = ""
    var age: Int = 29
    var weightKg: Double = 70
    var male: Bool = true
    var waterGoalMl: Int = 2500
    var glassMl: Int = 250
    var maxHR: Int { Int(208 - 0.7 * Double(age)) }

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        age = try c.decodeIfPresent(Int.self, forKey: .age) ?? 29
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? 70
        male = try c.decodeIfPresent(Bool.self, forKey: .male) ?? true
        waterGoalMl = try c.decodeIfPresent(Int.self, forKey: .waterGoalMl) ?? 2500
        glassMl = try c.decodeIfPresent(Int.self, forKey: .glassMl) ?? 250
    }

    enum CodingKeys: String, CodingKey { case name, age, weightKg, male, waterGoalMl, glassMl }
}

enum BPCategory {
    case normal, elevated, stage1, stage2, crisis

    init(sys: Int, dia: Int) {
        if sys > 180 || dia > 120 { self = .crisis }
        else if sys >= 140 || dia >= 90 { self = .stage2 }
        else if sys >= 130 || dia >= 80 { self = .stage1 }
        else if sys >= 120 { self = .elevated }
        else { self = .normal }
    }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .stage1: return "High · stage 1"
        case .stage2: return "High · stage 2"
        case .crisis: return "Very high"
        }
    }

    var color: Color {
        switch self {
        case .normal: return Theme.green
        case .elevated: return Theme.amber
        case .stage1: return Theme.orange
        case .stage2, .crisis: return Theme.red
        }
    }
}

/// Saves heart-rate history, workouts, measurements and the profile on the phone,
/// and turns heart rate into estimates (strain, calories, zones, recovery).
final class Store: ObservableObject {
    @Published var profile = Profile() { didSet { save() } }
    @Published var samples: [HRSample] = []
    @Published var workouts: [Workout] = []
    @Published var bp: [BPReading] = []
    @Published var hrChecks: [HRCheck] = []
    @Published var water: [WaterDay] = []

    // Live workout
    @Published var activeType: String?
    @Published var activeStart: Date?
    @Published var activeSamples: [HRSample] = []

    private var lastSampleTime = Date.distantPast
    private var loading = false
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("band-data.json")
    }()

    private struct Saved: Codable {
        var profile: Profile
        var samples: [HRSample]
        var workouts: [Workout]
        var bp: [BPReading]?
        var hrChecks: [HRCheck]?
        var water: [WaterDay]?
    }

    init() { load() }

    func load() {
        guard let d = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(Saved.self, from: d) else { return }
        loading = true
        samples = s.samples
        workouts = s.workouts
        bp = s.bp ?? []
        hrChecks = s.hrChecks ?? []
        water = s.water ?? []
        profile = s.profile
        loading = false
        trim()
    }

    func save() {
        if loading { return }
        let s = Saved(profile: profile, samples: samples, workouts: workouts, bp: bp, hrChecks: hrChecks, water: water)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: fileURL, options: .atomic) }
    }

    func trim() {
        let cutoff = Date().addingTimeInterval(-14 * 86400)
        samples.removeAll { $0.t < cutoff }
    }

    func resetAll() {
        samples = []
        workouts = []
        bp = []
        hrChecks = []
        water = []
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

    // MARK: Water

    static func dayKey(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    var waterToday: Int { water.first { $0.day == Self.dayKey() }?.ml ?? 0 }

    func addWater(_ ml: Int) {
        let key = Self.dayKey()
        if let i = water.firstIndex(where: { $0.day == key }) {
            water[i].ml = max(0, water[i].ml + ml)
        } else if ml > 0 {
            water.append(WaterDay(day: key, ml: ml))
        }
        if water.count > 60 { water.removeFirst(water.count - 60) }
        save()
    }

    /// Water for the last 7 days, oldest first.
    var waterWeek: [WaterBar] {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "EEEEE"
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i - 6, to: Date()) ?? Date()
            let key = Self.dayKey(d)
            return WaterBar(index: i, label: f.string(from: d), ml: water.first { $0.day == key }?.ml ?? 0)
        }
    }

    // MARK: Blood pressure and heart checks

    func addBP(_ r: BPReading) {
        bp.append(r)
        bp.sort { $0.date < $1.date }
        save()
    }

    func deleteBP(_ id: UUID) {
        bp.removeAll { $0.id == id }
        save()
    }

    func addHRCheck(_ c: HRCheck) {
        hrChecks.append(c)
        if hrChecks.count > 200 { hrChecks.removeFirst(hrChecks.count - 200) }
        save()
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

    private func lowHR(_ s: [HRSample]) -> Int? {
        let v = s.map { $0.bpm }.sorted()
        guard v.count >= 20 else { return nil }
        return v[v.count / 20]
    }

    /// Lowest steady heart rate seen in the last 24 hours (an estimate of resting HR).
    var restingHR: Int? {
        lowHR(samples.filter { $0.t > Date().addingTimeInterval(-86400) })
            ?? lowHR(samples.filter { $0.t > Date().addingTimeInterval(-3 * 86400) })
    }

    /// Readiness from how today's resting HR compares with your usual one.
    /// Needs at least two earlier days of heart-rate data.
    var recovery: Int? {
        guard let todayRHR = restingHR else { return nil }
        let cal = Calendar.current
        var past: [Int] = []
        for back in 1...7 {
            guard let dayStart = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: Date())),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            if let r = lowHR(samples.filter { $0.t >= dayStart && $0.t < dayEnd }) { past.append(r) }
        }
        guard past.count >= 2 else { return nil }
        let base = Double(past.reduce(0, +)) / Double(past.count)
        let score = 66 + (base - Double(todayRHR)) * 6
        return Int(max(1, min(99, score)))
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
    let s = max(0, Int(t))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

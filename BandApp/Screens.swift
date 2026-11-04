import SwiftUI

let zoneColors: [Color] = [Theme.blue, Theme.green, Theme.amber, Color(red: 0.96, green: 0.48, blue: 0.24), Theme.red]

struct ZoneBars: View {
    let seconds: [Double]
    var body: some View {
        let total = max(seconds.reduce(0, +), 1)
        VStack(spacing: 6) {
            ForEach(Array((0..<5).reversed()), id: \.self) { i in
                HStack(spacing: 8) {
                    Text("\(i + 1)").font(.system(size: 12)).foregroundColor(Theme.muted).frame(width: 14)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule().fill(zoneColors[i]).frame(width: g.size.width * seconds[i] / total)
                        }
                    }
                    .frame(height: 6)
                    Text(fmtDuration(seconds[i])).font(.system(size: 12, design: .rounded)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let note: String
    var sample = false
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                HStack { Label2(t: title); Spacer(); if sample { SampleTag() } }
                Text(value).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                Text(note).font(.system(size: 11)).foregroundColor(sample ? Theme.muted : Theme.green)
            }
        }
    }
}

// MARK: Health

struct HealthView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: Store

    var body: some View {
        let today = store.today.map { $0.bpm }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Health").font(.system(size: 26, weight: .semibold)).padding(.bottom, 4)

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label2(t: "Heart rate today")
                            Spacer()
                            Text(ble.heartRate.map { "\($0) bpm now" } ?? "--").font(.system(size: 13)).foregroundColor(Theme.red)
                        }
                        Sparkline(values: Array(today.suffix(400)), color: Theme.red, height: 70)
                        HStack {
                            mini("Lowest", today.min())
                            mini("Average", today.isEmpty ? nil : today.reduce(0, +) / today.count)
                            mini("Highest", today.max())
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label2(t: "Time in heart rate zones today")
                        ZoneBars(seconds: store.todayZones)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    MetricCard(title: "Resting HR", value: store.restingHR.map { "\($0) bpm" } ?? "--", note: "From your band")
                    MetricCard(title: "Max HR", value: "\(store.profile.maxHR) bpm", note: "From your age")
                    MetricCard(title: "HRV", value: "68 ms", note: "Not measured yet", sample: true)
                    MetricCard(title: "Blood oxygen", value: "97%", note: "Not measured yet", sample: true)
                    MetricCard(title: "Respiratory rate", value: "14.6 rpm", note: "Not measured yet", sample: true)
                    MetricCard(title: "Skin temp", value: "+0.2 °C", note: "Not measured yet", sample: true)
                }

                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Label2(t: "Heart screener · ECG"); Spacer(); SampleTag() }
                        Text("Your band has no ECG sensor, so this cannot be measured. Never use this app for medical decisions.")
                            .font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Label2(t: "Blood pressure"); Spacer(); SampleTag() }
                        Text("118/76").font(.system(size: 24, weight: .medium, design: .rounded))
                        Text("Example only. Use a real blood pressure cuff to check.")
                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    func mini(_ t: String, _ v: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label2(t: t)
            Text(v.map { "\($0)" } ?? "--").font(.system(size: 18, weight: .medium, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Sleep (sample until decoded)

struct SleepView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Sleep").font(.system(size: 26, weight: .semibold)); Spacer(); SampleTag() }
                Card {
                    HStack {
                        VStack(alignment: .leading) {
                            Label2(t: "Sleep performance")
                            Text("90%").font(.system(size: 40, weight: .medium, design: .rounded))
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("7:48").font(.system(size: 22, weight: .medium, design: .rounded))
                            Label2(t: "Hours of sleep")
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label2(t: "Stages")
                        stage("Awake", "0:31", 0.07, Theme.muted)
                        stage("Light", "3:58", 0.51, Theme.sleep)
                        stage("REM", "1:52", 0.24, Color(red: 0.61, green: 0.48, blue: 1))
                        stage("Deep", "1:27", 0.18, Color(red: 0.31, green: 0.48, blue: 1))
                    }
                }
                Card {
                    Text("Your band keeps sleep data inside Podsfine. Once Detective decodes it, real sleep shows here.")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    func stage(_ n: String, _ t: String, _ f: Double, _ c: Color) -> some View {
        HStack(spacing: 8) {
            Text(n).font(.system(size: 13)).frame(width: 52, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(c).frame(width: g.size.width * f)
                }
            }.frame(height: 8)
            Text(t).font(.system(size: 13, design: .rounded)).frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: Workout

struct WorkoutView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: Store
    @State private var type = "Running"
    let types = ["Running", "Walking", "Cycling", "Strength", "Football", "Cricket", "Gym", "Other"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.activeType == nil ? "Start activity" : store.activeType!)
                    .font(.system(size: 26, weight: .semibold))

                if store.activeStart == nil {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                        ForEach(types, id: \.self) { t in
                            Button { type = t } label: {
                                Text(t).font(.system(size: 15))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(type == t ? Theme.green.opacity(0.18) : Theme.card)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(type == t ? Theme.green : Theme.line))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    if ble.connected == nil {
                        Text("Your band is not connected. Connect it in Detective first so heart rate is recorded.")
                            .font(.system(size: 13)).foregroundColor(Theme.amber)
                    }
                    Button { store.startWorkout(type) } label: {
                        Text("Start \(type)").font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.white).foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    live
                }

                if !store.workouts.isEmpty {
                    Label2(t: "History").padding(.top, 8)
                    ForEach(store.workouts.sorted { $0.start > $1.start }.prefix(20)) { w in
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(w.type).font(.system(size: 15, weight: .medium))
                                    Spacer()
                                    Text(w.start, format: .dateTime.day().month().hour().minute()).font(.system(size: 12)).foregroundColor(Theme.muted)
                                }
                                HStack {
                                    small("Strain", String(format: "%.1f", w.strain))
                                    small("Time", fmtDuration(w.duration))
                                    small("Avg HR", "\(w.avgHR)")
                                    small("kcal", "\(w.calories)")
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    var live: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let s = store.activeSamples
            VStack(spacing: 10) {
                Text(fmtDuration(Date().timeIntervalSince(store.activeStart ?? Date())))
                    .font(.system(size: 56, weight: .medium, design: .rounded)).monospacedDigit()
                HStack {
                    small("Heart rate", ble.heartRate.map { "\($0)" } ?? "--")
                    small("Zone", ble.heartRate.map { "\(max(store.zone(for: $0), 1))" } ?? "--")
                    small("Strain", String(format: "%.1f", Store.strain(trimp: store.trimp(s))))
                    small("kcal", "\(Int(store.calories(s)))")
                }
                Card { ZoneBars(seconds: store.zones(s)) }
                Button { store.stopWorkout() } label: {
                    Text("Finish").font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.red).foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    func small(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label2(t: t)
            Text(v).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: More

struct MoreView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: Store
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    TextField("Your name", text: $store.profile.name)
                    Stepper("Age: \(store.profile.age)", value: $store.profile.age, in: 10...90)
                    Stepper("Weight: \(Int(store.profile.weightKg)) kg", value: $store.profile.weightKg, in: 30...200, step: 1)
                    Picker("Body", selection: $store.profile.male) {
                        Text("Male").tag(true)
                        Text("Female").tag(false)
                    }
                    Text("Used to estimate max heart rate (\(store.profile.maxHR) bpm), strain and calories.")
                        .font(.footnote).foregroundColor(Theme.muted)
                }
                Section("Band") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(ble.connected == nil ? "Not connected" : ble.connectedName).foregroundColor(Theme.muted)
                    }
                    Button("Reconnect") { ble.reconnectSaved() }
                    Button("Forget this band", role: .destructive) { ble.forgetBand() }
                }
                Section("Your data") {
                    HStack { Text("Heart rate readings saved"); Spacer(); Text("\(store.samples.count)").foregroundColor(Theme.muted) }
                    HStack { Text("Activities saved"); Spacer(); Text("\(store.workouts.count)").foregroundColor(Theme.muted) }
                    Button("Delete all data", role: .destructive) { confirmReset = true }
                }
                Section {
                    Text("Real: heart rate, battery, resting HR, zones. Estimated from heart rate: strain, calories. Marked Sample: not measured by your band. This app is not a medical device.")
                        .font(.footnote).foregroundColor(Theme.muted)
                } header: { Text("What's real") }
            }
            .navigationTitle("More")
            .confirmationDialog("Delete all saved heart rate and activities?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.resetAll() }
            }
        }
    }
}

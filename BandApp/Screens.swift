import SwiftUI

// MARK: Health

struct HealthView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: Store

    var body: some View {
        let today = store.today.map { $0.bpm }
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTitle(title: "Health", subtitle: "From your band")

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            IconBadge(symbol: "heart.fill", color: Theme.red)
                            Label2(t: "Heart rate today")
                            Spacer()
                            if let hr = ble.heartRate {
                                PulsingHeart(bpm: hr, size: 12)
                                Text("\(hr) now").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.red)
                            }
                        }
                        Sparkline(values: Array(today.suffix(400)), color: Theme.red, height: 80)
                        HStack {
                            mini("Lowest", today.min())
                            mini("Average", today.isEmpty ? nil : today.reduce(0, +) / today.count)
                            mini("Highest", today.max())
                        }
                    }
                }
                .appear(1)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    metric("Recovery", "bolt.heart.fill", Theme.green, store.recovery.map { "\($0)%" }, store.recovery == nil ? "Needs 3 days" : "Today").appear(2)
                    metric("Resting HR", "heart.circle.fill", Theme.red, store.restingHR.map { "\($0) bpm" }, "Last 24 hours").appear(3)
                    metric("Day strain", "flame.fill", Theme.blue, store.todayStrain.map { String(format: "%.1f", $0) }, "Out of 21").appear(4)
                    metric("Max HR", "speedometer", Theme.orange, "\(store.profile.maxHR) bpm", "From your age").appear(5)
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            IconBadge(symbol: "chart.bar.fill", color: Theme.amber)
                            Label2(t: "Time in heart rate zones today")
                        }
                        ZoneBars(seconds: store.todayZones)
                    }
                }
                .appear(6)

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            IconBadge(symbol: "drop.fill", color: Theme.purple)
                            Label2(t: "Blood pressure")
                            Spacer()
                            if let last = store.bp.last {
                                let cat = BPCategory(sys: last.systolic, dia: last.diastolic)
                                Text(cat.title).font(.system(size: 12, weight: .semibold)).foregroundColor(cat.color)
                            }
                        }
                        if let last = store.bp.last {
                            Text("\(last.systolic)/\(last.diastolic) mmHg")
                                .font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                            Text(last.date, format: .dateTime.day().month().hour().minute())
                                .font(.system(size: 12)).foregroundColor(Theme.muted)
                        } else {
                            Text("No readings yet. Add one in Measure.").font(.system(size: 13)).foregroundColor(Theme.muted)
                        }
                    }
                }
                .appear(7)

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            IconBadge(symbol: "drop.circle.fill", color: Theme.water)
                            Label2(t: "Water today")
                            Spacer()
                            Text(String(format: "%.1f / %.1f L", Double(store.waterToday) / 1000, Double(store.profile.waterGoalMl) / 1000))
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.water)
                        }
                        ProgressBar(fraction: Double(store.waterToday) / Double(max(store.profile.waterGoalMl, 1)), color: Theme.water)
                    }
                }
                .appear(8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    func mini(_ t: String, _ v: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label2(t: t)
            if let v = v {
                CountText(value: Double(v), size: 20)
            } else {
                Text("--").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func metric(_ title: String, _ symbol: String, _ color: Color, _ value: String?, _ note: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconBadge(symbol: symbol, color: color, size: 26)
                    Label2(t: title)
                }
                Text(value ?? "--")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(value == nil ? Theme.muted : Theme.text)
                Text(note).font(.system(size: 11)).foregroundColor(Theme.muted)
            }
        }
    }
}

struct ProgressBar: View {
    let fraction: Double
    let color: Color
    @State private var shown = 0.0
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(color).frame(width: g.size.width * shown)
                    .shadow(color: color.opacity(0.5), radius: 4)
            }
        }
        .frame(height: 8)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.2)) { shown = max(0, min(1, fraction)) } }
        .onChange(of: fraction) { f in withAnimation(Theme.spring) { shown = max(0, min(1, f)) } }
    }
}

// MARK: Start (workouts)

struct ActivityType: Identifiable {
    var id: String { name }
    let name: String
    let symbol: String
}

let activityTypes: [ActivityType] = [
    ActivityType(name: "Running", symbol: "figure.run"),
    ActivityType(name: "Walking", symbol: "figure.walk"),
    ActivityType(name: "Cycling", symbol: "bicycle"),
    ActivityType(name: "Strength", symbol: "dumbbell.fill"),
    ActivityType(name: "Football", symbol: "soccerball"),
    ActivityType(name: "Cricket", symbol: "cricket.ball.fill"),
    ActivityType(name: "Yoga", symbol: "figure.mind.and.body"),
    ActivityType(name: "Other", symbol: "sparkles"),
]

func activitySymbol(_ name: String) -> String {
    activityTypes.first { $0.name == name }?.symbol ?? "sparkles"
}

struct WorkoutView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: Store
    @State private var type = "Running"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                ScreenTitle(title: store.activeType ?? "Start activity", subtitle: store.activeType == nil ? "Pick what you're doing" : "Recording")

                if store.activeStart == nil {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(Array(activityTypes.enumerated()), id: \.element.id) { item in
                            let a = item.element
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { type = a.name }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: a.symbol).font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(type == a.name ? Theme.green : Theme.text)
                                        .frame(width: 24)
                                    Text(a.name).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 52)
                                .background(type == a.name ? Theme.green.opacity(0.15) : Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(type == a.name ? Theme.green : Theme.line, lineWidth: type == a.name ? 1.5 : 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                            .appear(item.offset + 1)
                        }
                    }
                    if ble.connected == nil {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text("Your band isn't connected, so heart rate won't be recorded.")
                        }
                        .font(.system(size: 13)).foregroundColor(Theme.amber)
                    }
                    BigButton(title: "Start \(type)", symbol: "play.fill") {
                        withAnimation(Theme.spring) { store.startWorkout(type) }
                    }
                    .appear(9)
                } else {
                    live
                }

                if !store.workouts.isEmpty {
                    Label2(t: "History").padding(.top, 8)
                    ForEach(Array(store.workouts.sorted { $0.start > $1.start }.prefix(20).enumerated()), id: \.element.id) { item in
                        let w = item.element
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    IconBadge(symbol: activitySymbol(w.type), color: Theme.blue)
                                    Text(w.type).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
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
                        .appear(min(item.offset, 6) + 10)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    var live: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let s = store.activeSamples
            VStack(spacing: 14) {
                ZStack {
                    Ring(fraction: Store.strain(trimp: store.trimp(s)) / 21, color: Theme.blue, lineWidth: 12)
                    VStack(spacing: 4) {
                        Image(systemName: activitySymbol(store.activeType ?? "")).font(.system(size: 22)).foregroundColor(Theme.blue)
                        Text(fmtDuration(Date().timeIntervalSince(store.activeStart ?? Date())))
                            .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(Theme.text)
                        Text("Strain \(String(format: "%.1f", Store.strain(trimp: store.trimp(s))))")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.blue)
                    }
                }
                .frame(width: 240, height: 240)
                .frame(maxWidth: .infinity)

                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label2(t: "Heart rate")
                            HStack(spacing: 6) {
                                PulsingHeart(bpm: ble.heartRate, size: 14)
                                Text(ble.heartRate.map { "\($0)" } ?? "--")
                                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundColor(Theme.text)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        small("Zone", ble.heartRate.map { "\(max(store.zone(for: $0), 1))" } ?? "--")
                        small("kcal", "\(Int(store.calories(s)))")
                    }
                }
                Card { ZoneBars(seconds: store.zones(s)) }
                BigButton(title: "Finish", symbol: "stop.fill", color: Theme.red, textColor: .white) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(Theme.spring) { store.stopWorkout() }
                }
            }
        }
    }

    func small(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label2(t: t)
            Text(v).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit().foregroundColor(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: More

struct MoreView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: Store
    @EnvironmentObject var vibes: VibeCenter
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { DetectiveView() } label: {
                        row("Connect band", ble.connected == nil ? "Not connected" : ble.connectedName,
                            "antenna.radiowaves.left.and.right", ble.connected == nil ? Theme.red : Theme.green)
                    }
                    NavigationLink { VibrationView(player: vibes.player) } label: {
                        row("Vibrations", "Patterns, calls, alarms, reminders", "waveform.path", Theme.amber)
                    }
                    if ble.isWPBand {
                        Button {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            ble.findBand()
                        } label: {
                            row("Find my band", "Makes your band vibrate", "bell.and.waves.left.and.right.fill", Theme.amber)
                        }
                        Button { ble.wpRefresh() } label: {
                            row("Refresh from band", "Steps and battery", "arrow.clockwise", Theme.green)
                        }
                    }
                    Button { ble.reconnectSaved() } label: {
                        row("Reconnect", "Try the saved band again", "arrow.triangle.2.circlepath", Theme.blue)
                    }
                    Button { ble.forgetBand() } label: {
                        row("Forget band", "Pick a different band next time", "xmark.circle.fill", Theme.muted)
                    }
                } header: { Text("Band") }

                Section {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "person.fill", color: Theme.green)
                        TextField("Your name", text: $store.profile.name)
                    }
                    Stepper(value: $store.profile.age, in: 10...90) {
                        row("Age", "\(store.profile.age) years", "calendar", Theme.amber)
                    }
                    Stepper(value: $store.profile.weightKg, in: 30...200, step: 1) {
                        row("Weight", "\(Int(store.profile.weightKg)) kg", "scalemass.fill", Theme.orange)
                    }
                    Picker(selection: $store.profile.male) {
                        Text("Male").tag(true)
                        Text("Female").tag(false)
                    } label: {
                        row("Body", "For calorie maths", "figure.stand", Theme.blue)
                    }
                } header: { Text("About you") } footer: {
                    Text("Used for max heart rate (\(store.profile.maxHR) bpm), strain and calories.")
                }

                Section {
                    Stepper(value: $store.profile.waterGoalMl, in: 1000...6000, step: 250) {
                        row("Daily goal", String(format: "%.2f L", Double(store.profile.waterGoalMl) / 1000), "target", Theme.water)
                    }
                    Stepper(value: $store.profile.glassMl, in: 100...1000, step: 50) {
                        row("Glass size", "\(store.profile.glassMl) ml", "cup.and.saucer.fill", Theme.water)
                    }
                } header: { Text("Water") }

                Section {
                    row("Heart rate readings", "\(store.samples.count) saved", "heart.text.square.fill", Theme.red)
                    row("Activities", "\(store.workouts.count) saved", "figure.run", Theme.blue)
                    row("Blood pressure", "\(store.bp.count) saved", "drop.fill", Theme.purple)
                    Button(role: .destructive) { confirmReset = true } label: {
                        row("Delete all data", "Can't be undone", "trash.fill", Theme.red)
                    }
                } header: { Text("Your data") } footer: {
                    Text("Everything stays on this iPhone. This app is not a medical device.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("More")
            .confirmationDialog("Delete all saved data?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.resetAll() }
            }
        }
    }

    func row(_ title: String, _ sub: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15)).foregroundColor(Theme.text)
                Text(sub).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
    }
}

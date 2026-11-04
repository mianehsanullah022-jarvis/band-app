import SwiftUI

struct HomeView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: Store
    let goTo: (AppTab) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                header.appear(0)

                HStack(spacing: 0) {
                    Dial(value: steps.map { $0 >= 10000 ? String(format: "%.1fk", Double($0) / 1000) : "\($0)" } ?? "--",
                         label: "Steps",
                         fraction: Double(steps ?? 0) / Double(max(store.profile.stepsGoal, 1)),
                         color: Theme.green)
                        .frame(maxWidth: .infinity)
                    Dial(value: store.recovery.map { "\($0)%" } ?? "--",
                         label: "Recovery",
                         fraction: Double(store.recovery ?? 0) / 100,
                         color: recoveryColor)
                        .frame(maxWidth: .infinity)
                    Dial(value: store.todayStrain.map { String(format: "%.1f", $0) } ?? "--",
                         label: "Strain",
                         fraction: (store.todayStrain ?? 0) / 21,
                         color: Theme.blue)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 6)
                .appear(1)

                Card {
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(symbol: "text.bubble.fill", color: Theme.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Label2(t: "Today in one line")
                            Text(insight).font(.system(size: 14)).foregroundColor(Theme.text.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .appear(2)

                Button { goTo(.measure) } label: {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                IconBadge(symbol: "drop.circle.fill", color: Theme.water)
                                Label2(t: "Water")
                                Spacer()
                                Text(String(format: "%.1f / %.1f L", Double(store.waterToday) / 1000, Double(store.profile.waterGoalMl) / 1000))
                                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.water)
                            }
                            ProgressBar(fraction: Double(store.waterToday) / Double(max(store.profile.waterGoalMl, 1)), color: Theme.water)
                        }
                    }
                }
                .buttonStyle(PressStyle())
                .appear(2)

                if let msg = hint {
                    Card {
                        HStack(spacing: 12) {
                            IconBadge(symbol: "sparkles", color: Theme.green)
                            Text(msg).font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.85))
                        }
                    }
                    .appear(2)
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            IconBadge(symbol: "heart.fill", color: Theme.red)
                            Label2(t: "Heart rate")
                            Spacer()
                            if let hr = ble.heartRate ?? store.hrChecks.last?.bpm {
                                PulsingHeart(bpm: hr, size: 14)
                                Text("\(hr)")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .animation(.easeOut(duration: 0.3), value: hr)
                                Text("bpm").font(.system(size: 12)).foregroundColor(Theme.muted)
                            } else {
                                Text("--").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
                            }
                        }
                        Sparkline(values: Array(store.today.map { $0.bpm }.suffix(60)), color: Theme.red)
                        HStack {
                            Text(ble.hrMeasuring ? "Band is measuring…" : "Tap to check your heart rate now")
                                .font(.system(size: 12)).foregroundColor(Theme.muted)
                            Spacer()
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                ble.measureHeartRate()
                            } label: {
                                Label("Measure", systemImage: "heart.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Theme.red.opacity(0.18))
                                    .foregroundColor(Theme.red)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(PressStyle())
                            .disabled(!ble.isWPBand || ble.hrMeasuring)
                            .opacity(!ble.isWPBand || ble.hrMeasuring ? 0.5 : 1)
                        }
                    }
                }
                .appear(3)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    stat("Resting HR", "heart.circle.fill", Theme.red, store.restingHR.map { Double($0) }, unit: "bpm").appear(4)
                    stat("Calories", "flame.fill", Theme.orange, store.todayCalories.map { Double($0) }, unit: "kcal").appear(5)
                    stat("Battery", "battery.75", Theme.green, ble.battery.map { Double($0) }, unit: "%").appear(6)
                    bpStat.appear(7)
                }

                Button { goTo(.measure) } label: {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "waveform.path.ecg", color: Theme.green, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Measure now").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                            Text("Heart rate, heart rhythm, blood pressure, water").font(.system(size: 12)).foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(Theme.muted)
                    }
                    .padding(14)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.green.opacity(0.35), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .appear(8)

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            IconBadge(symbol: "figure.run", color: Theme.blue)
                            Label2(t: "Today's activities")
                            Spacer()
                            Button("Start") { goTo(.start) }.font(.system(size: 13, weight: .semibold))
                        }
                        if store.todayWorkouts.isEmpty {
                            Text("No activities yet today.").font(.system(size: 13)).foregroundColor(Theme.muted)
                        }
                        ForEach(store.todayWorkouts) { w in
                            HStack {
                                Text("\(w.type) · \(fmtDuration(w.duration))").font(.system(size: 14)).foregroundColor(Theme.text)
                                Spacer()
                                Text(String(format: "%.1f", w.strain))
                                    .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(Theme.blue)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .appear(9)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    var steps: Int? { ble.steps ?? store.stepsToday }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return store.profile.name.isEmpty ? part : "\(part), \(store.profile.name)"
    }

    /// A plain sentence about today, built from real numbers only.
    var insight: String {
        var parts: [String] = []
        if let s = steps {
            let left = store.profile.stepsGoal - s
            parts.append(left > 0 ? "\(left) steps to your goal" : "Step goal done 🎉")
            let week = store.stepsWeek
            if week.count == 7, week[5].ml > 0 {
                let diff = s - week[5].ml
                parts.append(diff >= 0 ? "\(diff) more than yesterday" : "\(-diff) fewer than yesterday so far")
            }
        }
        if let hr = store.hrChecks.last { parts.append("last heart rate \(hr.bpm) bpm") }
        let waterLeft = store.profile.waterGoalMl - store.waterToday
        if waterLeft > 0 { parts.append(String(format: "%.1f L water to go", Double(waterLeft) / 1000)) }
        if parts.isEmpty { return "Connect your band and measure your heart rate to see your day here." }
        let line = parts.joined(separator: " · ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    var recoveryColor: Color {
        guard let r = store.recovery else { return Theme.green }
        return r >= 67 ? Theme.green : (r >= 34 ? Theme.amber : Theme.red)
    }

    var hint: String? {
        if ble.connected == nil { return "Your band isn't connected. Go to More → Connect band." }
        if store.recovery == nil { return "Wear your band for 3 days and your daily Recovery score appears here." }
        return nil
    }

    var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.weekday(.wide).day().month())
                    .font(.system(size: 13)).foregroundColor(Theme.muted)
                Text(greeting)
                    .font(.system(size: 30, weight: .bold)).foregroundColor(Theme.text)
            }
            Spacer()
            Button { goTo(.more) } label: {
                HStack(spacing: 6) {
                    Circle().fill(ble.connected == nil ? Theme.red : Theme.green).frame(width: 8, height: 8)
                    Text(ble.connected == nil ? "Not connected" : "\(ble.connectedName)\(ble.battery.map { " · \($0)%" } ?? "")")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.text.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.card).clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(PressStyle())
        }
    }

    func stat(_ title: String, _ symbol: String, _ color: Color, _ value: Double?, unit: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconBadge(symbol: symbol, color: color, size: 26)
                    Label2(t: title)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let v = value {
                        CountText(value: v, size: 24)
                    } else {
                        Text("--").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
                    }
                    Text(unit).font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
        }
    }

    var bpStat: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconBadge(symbol: "drop.fill", color: Theme.purple, size: 26)
                    Label2(t: "Blood pressure")
                }
                if let last = store.bp.last {
                    Text("\(last.systolic)/\(last.diastolic)")
                        .font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                } else {
                    Text("--").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
                }
            }
        }
    }
}

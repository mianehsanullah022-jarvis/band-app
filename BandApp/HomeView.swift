import SwiftUI

struct Dial: View {
    let value: String
    let label: String
    let fraction: Double
    let color: Color
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 7)
                Circle().trim(from: 0, to: max(0, min(1, fraction)))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
            }
            .frame(width: 92, height: 92)
            Label2(t: label)
        }
        .foregroundColor(.white)
    }
}

struct Sparkline: View {
    let values: [Int]
    let color: Color
    var height: CGFloat = 40
    var body: some View {
        GeometryReader { g in
            if values.count > 1, let lo = values.min(), let hi = values.max() {
                let span = max(Double(hi - lo), 1)
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = g.size.width * Double(i) / Double(values.count - 1)
                        let y = g.size.height * (1 - Double(v - lo) / span)
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            } else {
                Text("Waiting for live data…").font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
        .frame(height: height)
    }
}

struct HomeView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    header

                    HStack(spacing: 0) {
                        NavigationLink { SleepView() } label: {
                            Dial(value: "90%", label: "Sleep", fraction: 0.9, color: Theme.sleep)
                        }.frame(maxWidth: .infinity)
                        Dial(value: "74%", label: "Recovery", fraction: 0.74, color: Theme.green).frame(maxWidth: .infinity)
                        Dial(value: store.todayStrain.map { String(format: "%.1f", $0) } ?? "--",
                             label: "Strain", fraction: (store.todayStrain ?? 0) / 21, color: Theme.blue)
                            .frame(maxWidth: .infinity)
                    }
                    Text("Sleep and recovery are samples · strain is estimated from your heart rate")
                        .font(.system(size: 11)).foregroundColor(Theme.muted).multilineTextAlignment(.center)

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label2(t: "Heart rate · live")
                                Spacer()
                                if let hr = ble.heartRate {
                                    Text("\(hr)").font(.system(size: 22, weight: .medium, design: .rounded)).foregroundColor(Theme.red)
                                    + Text(" bpm").font(.system(size: 12)).foregroundColor(Theme.muted)
                                } else {
                                    Text("--").font(.system(size: 22, weight: .medium)).foregroundColor(Theme.muted)
                                }
                            }
                            Sparkline(values: ble.hrHistory, color: Theme.red)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        stat("Resting HR", store.restingHR.map { "\($0) bpm" } ?? "--", real: true)
                        stat("Calories", store.todayCalories.map { "\($0)" } ?? "--", real: true)
                        stat("Battery", ble.battery.map { "\($0)%" } ?? "--", real: true)
                        stat("Steps", "7,842", real: false)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Label2(t: "Today's activities")
                            if store.todayWorkouts.isEmpty {
                                Text("No activities yet. Tap Start to record one.")
                                    .font(.system(size: 13)).foregroundColor(Theme.muted)
                            }
                            ForEach(store.todayWorkouts) { w in
                                HStack {
                                    Text("\(w.type) · \(fmtDuration(w.duration))").font(.system(size: 14))
                                    Spacer()
                                    Text(String(format: "%.1f", w.strain)).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundColor(Theme.blue)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.weekday(.wide).day().month())
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
                Text(store.profile.name.isEmpty ? "Today" : "Hi, \(store.profile.name)")
                    .font(.system(size: 26, weight: .semibold))
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(ble.connected == nil ? Theme.red : Theme.green).frame(width: 8, height: 8)
                Text(ble.connected == nil ? "Not connected" : "\(ble.connectedName)\(ble.battery.map { " · \($0)%" } ?? "")")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.card).clipShape(Capsule())
        }
        .padding(.bottom, 6)
    }

    func stat(_ title: String, _ value: String, real: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                HStack { Label2(t: title); Spacer(); if !real { SampleTag() } }
                Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
            }
        }
    }
}

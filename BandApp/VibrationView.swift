import SwiftUI

struct VibrationView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var vibes: VibeCenter
    @ObservedObject var player: VibePlayer
    @State private var showAdd = false

    var body: some View {
        List {
            if !ble.isWPBand {
                Section {
                    Text("Connect your band first (More → Connect band) to feel these.")
                        .font(.system(size: 13)).foregroundColor(Theme.amber)
                        .listRowBackground(Theme.card)
                }
            }

            Section {
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    player.stop()
                    ble.stopVibrate()
                } label: {
                    HStack {
                        Spacer()
                        Label("Stop vibration", systemImage: "stop.fill").font(.system(size: 16, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Theme.red)
            }

            Section {
                ForEach(0..<BLEManager.vibrateMethods.count, id: \.self) { i in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        ble.vibrateMethod = i
                        ble.stopVibrate()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ble.buzzOnce(seconds: 1.0) }
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: "\(i + 1).circle.fill", color: ble.vibrateMethod == i ? Theme.green : Theme.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Vibrate method \(i + 1)").font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
                                Text(ble.vibrateMethod == i ? "In use · tap to test again" : "Tap to test and use this one")
                                    .font(.system(size: 12)).foregroundColor(Theme.muted)
                            }
                            Spacer()
                            if ble.vibrateMethod == i {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.green).font(.system(size: 22))
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                    .disabled(!ble.isWPBand)
                }
            } header: { Text("Step 1 · Find the buzz") } footer: {
                Text("Tap each method: the band should buzz for 1 second and then stop. Keep the one that does that. All patterns use it.")
            }

            Section {
                ForEach(Vibes.all) { p in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if player.playing == p.id { player.stop() } else { player.play(p) }
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: p.symbol, color: player.playing == p.id ? Theme.green : Theme.amber)
                                .scaleEffect(player.playing == p.id ? 1.12 : 1)
                                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: player.playing)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
                                PatternDots(pattern: p, active: player.playing == p.id)
                            }
                            Spacer()
                            Image(systemName: player.playing == p.id ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(player.playing == p.id ? Theme.red : Theme.green)
                        }
                    }
                    .listRowBackground(Theme.card)
                    .disabled(!ble.isWPBand)
                }
            } header: { Text("Step 2 · Patterns, tap to feel") }

            Section {
                Toggle(isOn: $vibes.settings.callBuzz) {
                    rowLabel("Buzz for calls", "Keeps buzzing until you answer or decline", "phone.fill", Theme.green)
                }
                .listRowBackground(Theme.card)
            } header: { Text("Calls") } footer: {
                Text("Works while Band is open or in the background. If you swipe Band away, iPhone stops it.")
            }

            Section {
                ForEach($vibes.settings.alarms) { $a in
                    HStack(spacing: 12) {
                        IconBadge(symbol: "alarm.fill", color: Theme.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.timeText).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                            Text(a.label.isEmpty ? "Alarm" : a.label).font(.system(size: 12)).foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Toggle("", isOn: $a.enabled).labelsHidden()
                    }
                    .listRowBackground(Theme.card)
                }
                .onDelete { vibes.settings.alarms.remove(atOffsets: $0) }

                Button { showAdd = true } label: {
                    rowLabel("Add alarm", "Buzzes like a call until you tap Stop", "plus.circle.fill", Theme.orange)
                }
                .listRowBackground(Theme.card)
            } header: { Text("Alarms") }

            Section {
                Toggle(isOn: $vibes.settings.waterReminder) {
                    rowLabel("Drink water", "Every \(vibes.settings.waterEveryMin) min", "drop.fill", Theme.water)
                }
                .listRowBackground(Theme.card)
                if vibes.settings.waterReminder {
                    Stepper("Every \(vibes.settings.waterEveryMin) min", value: $vibes.settings.waterEveryMin, in: 15...240, step: 15)
                        .listRowBackground(Theme.card)
                    patternPicker($vibes.settings.waterPattern)
                }

                Toggle(isOn: $vibes.settings.standReminder) {
                    rowLabel("Stand up and move", "Every \(vibes.settings.standEveryMin) min", "figure.walk", Theme.green)
                }
                .listRowBackground(Theme.card)
                if vibes.settings.standReminder {
                    Stepper("Every \(vibes.settings.standEveryMin) min", value: $vibes.settings.standEveryMin, in: 15...240, step: 15)
                        .listRowBackground(Theme.card)
                    patternPicker($vibes.settings.standPattern)
                }

                Stepper("Quiet from \(vibes.settings.quietFrom):00", value: $vibes.settings.quietFrom, in: 0...23)
                    .listRowBackground(Theme.card)
                Stepper("Quiet until \(vibes.settings.quietTo):00", value: $vibes.settings.quietTo, in: 0...23)
                    .listRowBackground(Theme.card)
            } header: { Text("Reminders") } footer: {
                Text("No reminder buzzes during quiet hours.")
            }

            Section {
                Text("iPhone doesn't let any app see other apps' notifications (Snapchat, WhatsApp, Instagram, Gmail). Your band gets those straight from iPhone and vibrates in its own way.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
                    .listRowBackground(Theme.card)
            } header: { Text("App notifications") }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Vibrations")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            AddAlarmView { alarm in
                vibes.askNotificationPermission()
                withAnimation { vibes.settings.alarms.append(alarm) }
            }
            .presentationDetents([.medium])
        }
    }

    func patternPicker(_ sel: Binding<String>) -> some View {
        Picker("Pattern", selection: sel) {
            ForEach(Vibes.all.filter { $0.id != "call" }) { p in Text(p.name).tag(p.id) }
        }
        .listRowBackground(Theme.card)
    }

    func rowLabel(_ title: String, _ sub: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15)).foregroundColor(Theme.text)
                Text(sub).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
    }
}

/// Dots that show the rhythm of a pattern, lighting up while it plays.
struct PatternDots: View {
    let pattern: VibePattern
    let active: Bool
    @State private var lit = -1

    var body: some View {
        let total = max(pattern.length, 1)
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line).frame(height: 2).offset(y: 0)
                ForEach(0..<pattern.times.count, id: \.self) { i in
                    Circle()
                        .fill(i <= lit ? Theme.green : Theme.muted)
                        .frame(width: 8, height: 8)
                        .scaleEffect(i == lit ? 1.6 : 1)
                        .offset(x: (g.size.width - 8) * pattern.times[i] / total)
                }
            }
            .frame(height: 10)
        }
        .frame(width: 140, height: 10)
        .onChange(of: active) { on in
            lit = -1
            guard on else { return }
            for (i, t) in pattern.times.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { lit = i }
                }
            }
        }
    }
}

struct AddAlarmView: View {
    let onAdd: (BandAlarm) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var label = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                TextField("Label (for example: Fajr, Gym, Meeting)", text: $label)
            }
            .navigationTitle("New alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let c = Calendar.current
                        onAdd(BandAlarm(hour: c.component(.hour, from: time), minute: c.component(.minute, from: time), label: label))
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Full-screen alert while a call, alarm or reminder is buzzing.
struct BuzzAlert: View {
    @EnvironmentObject var vibes: VibeCenter
    let text: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 26) {
                ZStack {
                    Circle().fill(Theme.orange.opacity(0.18)).frame(width: 170, height: 170)
                        .scaleEffect(pulse ? 1.15 : 0.9)
                    Image(systemName: vibes.callRinging ? "phone.fill" : "alarm.fill")
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundColor(Theme.orange)
                        .rotationEffect(.degrees(pulse ? 8 : -8))
                }
                Text(text).font(.system(size: 26, weight: .bold)).foregroundColor(Theme.text)
                    .multilineTextAlignment(.center)
                BigButton(title: "Stop", symbol: "stop.fill", color: Theme.orange, textColor: .black) {
                    vibes.stopAll()
                }
                .padding(.horizontal, 40)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

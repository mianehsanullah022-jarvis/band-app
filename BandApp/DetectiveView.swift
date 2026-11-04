import SwiftUI

/// Radar circles that pulse while scanning.
struct RadarPulse: View {
    let active: Bool
    @State private var go = false
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(Theme.green.opacity(0.5), lineWidth: 2)
                    .scaleEffect(go ? 1.6 : 0.4)
                    .opacity(go ? 0 : 0.9)
                    .animation(active ? .easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(i) * 0.6) : .default, value: go)
            }
            IconBadge(symbol: "antenna.radiowaves.left.and.right", color: Theme.green, size: 54)
        }
        .frame(width: 140, height: 140)
        .onAppear { go = active }
        .onChange(of: active) { a in go = a }
    }
}

struct DetectiveView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var writeTarget: CharInfo?
    @State private var hex = ""

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    RadarPulse(active: ble.scanning)
                    if ble.connected == nil {
                        BigButton(title: ble.scanning ? "Searching… (30 sec)" : "Find my band",
                                  symbol: ble.scanning ? "dot.radiowaves.left.and.right" : "magnifyingglass") {
                            ble.startScan()
                        }
                        .disabled(!ble.bluetoothOn || ble.scanning)
                        .opacity(!ble.bluetoothOn || ble.scanning ? 0.6 : 1)
                        if !ble.bluetoothOn {
                            Text("Turn on Bluetooth and allow Band to use it in Settings.")
                                .font(.footnote).foregroundColor(Theme.amber).multilineTextAlignment(.center)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.green).frame(width: 10, height: 10)
                            Text("Connected to \(ble.connectedName)").font(.system(size: 15, weight: .semibold))
                        }
                        Button("Disconnect", role: .destructive) { ble.disconnect() }
                            .buttonStyle(.borderless)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Theme.card)

                if ble.connected == nil {
                    ForEach(ble.devices) { d in
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            ble.connect(d)
                        } label: {
                            HStack(spacing: 12) {
                                IconBadge(symbol: d.rssi == 0 ? "link" : "applewatch.radiowaves.left.and.right", color: d.rssi == 0 ? Theme.green : Theme.blue)
                                Text(d.name).foregroundColor(Theme.text)
                                Spacer()
                                if d.rssi != 0 { SignalBars(rssi: d.rssi) }
                            }
                        }
                        .listRowBackground(Theme.card)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            } header: { Text("Connect") } footer: {
                Text("Hold the band right next to the phone. Your band is usually the one marked “connected”, or the one with the strongest signal.")
            }

            if !ble.chars.isEmpty {
                Section("What the band has") {
                    ForEach(ble.chars) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.uuid).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.text)
                            Text("in \(c.service) · \(c.props)").font(.system(size: 11)).foregroundColor(Theme.muted)
                            HStack(spacing: 14) {
                                if c.props.contains("read") {
                                    Button("Read") { ble.read(c) }.buttonStyle(.borderless)
                                }
                                if c.props.contains("write") {
                                    Button("Send") { writeTarget = c; hex = "" }.buttonStyle(.borderless)
                                }
                            }
                            .font(.system(size: 13))
                        }
                        .listRowBackground(Theme.card)
                    }
                }
            }

            Section {
                ShareLink(item: ble.logText) {
                    Label("Share log with Claude", systemImage: "square.and.arrow.up")
                }
                .listRowBackground(Theme.card)
                ForEach(ble.log.suffix(300).reversed()) { l in
                    Text(l.text).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.text.opacity(0.85))
                        .listRowBackground(Theme.card)
                }
            } header: { Text("Live log") }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .animation(Theme.spring, value: ble.devices.count)
        .navigationTitle("Connect band")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Send bytes", isPresented: Binding(get: { writeTarget != nil }, set: { if !$0 { writeTarget = nil } })) {
            TextField("Hex, for example AB 00 01", text: $hex)
            Button("Send") { if let t = writeTarget { ble.write(t, hex: hex) }; writeTarget = nil }
            Button("Cancel", role: .cancel) { writeTarget = nil }
        } message: {
            Text("Only send what Claude tells you to.")
        }
    }
}

struct SignalBars: View {
    let rssi: Int
    var level: Int { rssi > -55 ? 4 : rssi > -67 ? 3 : rssi > -80 ? 2 : 1 }
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= level ? Theme.green : Theme.line)
                    .frame(width: 4, height: CGFloat(4 + i * 3))
            }
        }
        .accessibilityLabel("Signal \(level) of 4")
    }
}

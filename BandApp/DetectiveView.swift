import SwiftUI

struct DetectiveView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var writeTarget: CharInfo?
    @State private var hex = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if ble.connected == nil {
                        Button(ble.scanning ? "Scanning… (15 sec)" : "Find my band") { ble.startScan() }
                            .disabled(!ble.bluetoothOn || ble.scanning)
                        if !ble.bluetoothOn {
                            Text("Turn on Bluetooth and allow Band to use it in Settings.").font(.footnote).foregroundColor(Theme.muted)
                        }
                        ForEach(ble.devices) { d in
                            Button {
                                ble.connect(d)
                            } label: {
                                HStack {
                                    Text(d.name).foregroundColor(.white)
                                    Spacer()
                                    Text("\(d.rssi) dBm").font(.footnote).foregroundColor(Theme.muted)
                                }
                            }
                        }
                    } else {
                        HStack {
                            Circle().fill(Theme.green).frame(width: 8, height: 8)
                            Text("Connected: \(ble.connectedName)")
                            Spacer()
                            Button("Disconnect", role: .destructive) { ble.disconnect() }
                        }
                    }
                } header: { Text("1 · Connect") } footer: {
                    Text("Tip: if your band does not show up, close Podsfine fully and try again.")
                }

                if !ble.chars.isEmpty {
                    Section("2 · What the band has") {
                        ForEach(ble.chars) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.uuid).font(.system(size: 12, design: .monospaced))
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
                        }
                    }
                }

                Section {
                    ShareLink(item: ble.logText) {
                        Label("Share log with Claude", systemImage: "square.and.arrow.up")
                    }
                    ForEach(ble.log.suffix(300).reversed()) { l in
                        Text(l.text).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                    }
                } header: { Text("3 · Live log") }
            }
            .navigationTitle("Detective")
            .alert("Send bytes", isPresented: Binding(get: { writeTarget != nil }, set: { if !$0 { writeTarget = nil } })) {
                TextField("Hex, for example AB 00 01", text: $hex)
                Button("Send") { if let t = writeTarget { ble.write(t, hex: hex) }; writeTarget = nil }
                Button("Cancel", role: .cancel) { writeTarget = nil }
            } message: {
                Text("Only send what Claude tells you to.")
            }
        }
    }
}

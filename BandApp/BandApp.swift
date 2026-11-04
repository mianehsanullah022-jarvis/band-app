import SwiftUI

@main
struct BandAppMain: App {
    @StateObject private var ble = BLEManager()
    @StateObject private var store = Store()
    @StateObject private var vibes = VibeCenter()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(store)
                .environmentObject(vibes)
                .preferredColorScheme(.dark)
                .tint(Theme.green)
                .onAppear {
                    vibes.attach(ble)
                    ble.onHeartRate = { [weak store] bpm in store?.addHR(bpm) }
                    ble.onHRResult = { [weak store] bpm in
                        store?.addHRCheck(HRCheck(date: Date(), bpm: bpm, low: bpm, high: bpm))
                    }
                    ble.onBPResult = { [weak store] sys, dia in
                        store?.addBP(BPReading(date: Date(), systolic: sys, diastolic: dia, pulse: nil, fromBand: true))
                    }
                }
                .onChange(of: phase) { p in if p != .active { store.save() } }
        }
    }
}

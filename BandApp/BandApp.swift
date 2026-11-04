import SwiftUI

@main
struct BandAppMain: App {
    @StateObject private var ble = BLEManager()
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.green)
                .onAppear { ble.onHeartRate = { [weak store] bpm in store?.addHR(bpm) } }
                .onChange(of: phase) { p in if p != .active { store.save() } }
        }
    }
}

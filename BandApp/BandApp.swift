import SwiftUI

@main
struct BandAppMain: App {
    @StateObject private var ble = BLEManager()
    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView().tabItem { Label("Home", systemImage: "house") }
                DetectiveView().tabItem { Label("Detective", systemImage: "antenna.radiowaves.left.and.right") }
            }
            .environmentObject(ble)
            .preferredColorScheme(.dark)
            .tint(Theme.green)
        }
    }
}

enum Theme {
    static let bg = Color.black
    static let card = Color(red: 0.067, green: 0.075, blue: 0.082)
    static let line = Color(red: 0.118, green: 0.129, blue: 0.145)
    static let muted = Color(red: 0.54, green: 0.565, blue: 0.596)
    static let green = Color(red: 0.18, green: 0.8, blue: 0.443)
    static let blue = Color(red: 0.227, green: 0.553, blue: 1.0)
    static let amber = Color(red: 0.96, green: 0.72, blue: 0.24)
    static let red = Color(red: 0.898, green: 0.282, blue: 0.302)
    static let sleep = Color(red: 0.79, green: 0.8, blue: 0.83)
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ c: () -> Content) { content = c() }
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct Label2: View {
    let t: String
    var body: some View { Text(t).font(.system(size: 12)).foregroundColor(Theme.muted) }
}

struct SampleTag: View {
    var body: some View {
        Text("Sample")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Theme.amber)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.amber.opacity(0.5), lineWidth: 1))
    }
}

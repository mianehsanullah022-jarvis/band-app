import SwiftUI

// MARK: Opening animation

struct HeartbeatLine: Shape {
    func path(in r: CGRect) -> Path {
        let pts: [(Double, Double)] = [(0, 0.5), (0.3, 0.5), (0.38, 0.28), (0.5, 0.78), (0.6, 0.38), (0.66, 0.5), (1, 0.5)]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let c = CGPoint(x: r.minX + r.width * pt.0, y: r.minY + r.height * pt.1)
            if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
        }
        return p
    }
}

struct SplashView: View {
    let done: () -> Void
    @State private var ring: CGFloat = 0
    @State private var green: CGFloat = 0
    @State private var line: CGFloat = 0
    @State private var logoScale: CGFloat = 0.7
    @State private var title = false
    @State private var out = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 28) {
                ZStack {
                    Circle().stroke(Theme.line, lineWidth: 14)
                    Circle().trim(from: 0, to: ring)
                        .stroke(Theme.text, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().trim(from: 0, to: green)
                        .stroke(Theme.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(165))
                        .shadow(color: Theme.green.opacity(0.6), radius: 10)
                    HeartbeatLine().trim(from: 0, to: line)
                        .stroke(Theme.text, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        .frame(width: 84, height: 54)
                }
                .frame(width: 130, height: 130)
                .scaleEffect(logoScale)

                VStack(spacing: 6) {
                    Text("BAND").font(.system(size: 30, weight: .heavy)).tracking(10).foregroundColor(Theme.text)
                    Text("Know your body").font(.system(size: 14)).foregroundColor(Theme.muted)
                }
                .opacity(title ? 1 : 0)
                .offset(y: title ? 0 : 12)
            }
            .scaleEffect(out ? 1.15 : 1)
            .opacity(out ? 0 : 1)
        }
        .onAppear(perform: run)
    }

    func run() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { logoScale = 1 }
        withAnimation(.easeInOut(duration: 0.9)) { ring = 0.67 }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) { green = 0.25 }
        withAnimation(.easeInOut(duration: 0.7).delay(0.9)) { line = 1 }
        withAnimation(.easeOut(duration: 0.5).delay(1.2)) { title = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        withAnimation(.easeIn(duration: 0.4).delay(2.1)) { out = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { done() }
    }
}

// MARK: Tabs

enum AppTab: Int, CaseIterable {
    case home, measure, start, health, more

    var title: String {
        switch self {
        case .home: return "Home"
        case .measure: return "Measure"
        case .start: return "Start"
        case .health: return "Health"
        case .more: return "More"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "circle.hexagongrid.fill"
        case .measure: return "waveform.path.ecg"
        case .start: return "figure.run"
        case .health: return "heart.text.square.fill"
        case .more: return "person.crop.circle.fill"
        }
    }
}

struct TabBar: View {
    @Binding var tab: AppTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { t in
                Button {
                    if tab != t {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { tab = t }
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if tab == t {
                                Capsule().fill(Theme.green.opacity(0.18))
                                    .matchedGeometryEffect(id: "pill", in: ns)
                                    .frame(width: 54, height: 30)
                            }
                            Image(systemName: t.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .scaleEffect(tab == t ? 1.12 : 1)
                        }
                        .frame(height: 30)
                        Text(t.title).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(tab == t ? Theme.green : Theme.muted)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(t.title)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            Rectangle().fill(Color.black.opacity(0.92))
                .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

struct RootView: View {
    @EnvironmentObject var vibes: VibeCenter
    @State private var tab: AppTab = .home
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Group {
                switch tab {
                case .home: HomeView(goTo: { t in withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { tab = t } })
                case .measure: MeasureView()
                case .start: WorkoutView()
                case .health: HealthView()
                case .more: MoreView()
                }
            }
            .id(tab)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(tab: $tab)
        }
        .overlay {
            if let a = vibes.alert {
                BuzzAlert(text: a)
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            }
        }
        .animation(Theme.spring, value: vibes.alert)
        .overlay {
            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.3)) { showSplash = false } }
                    .transition(.opacity)
            }
        }
    }
}

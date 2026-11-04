import SwiftUI

enum Theme {
    static let bg = Color.black
    static let card = Color(red: 0.067, green: 0.075, blue: 0.082)
    static let cardHi = Color(red: 0.094, green: 0.102, blue: 0.114)
    static let line = Color(red: 0.118, green: 0.129, blue: 0.145)
    static let muted = Color(red: 0.56, green: 0.585, blue: 0.616)
    static let text = Color(red: 0.96, green: 0.965, blue: 0.97)
    static let green = Color(red: 0.18, green: 0.8, blue: 0.443)
    static let blue = Color(red: 0.227, green: 0.553, blue: 1.0)
    static let amber = Color(red: 0.96, green: 0.72, blue: 0.24)
    static let orange = Color(red: 0.96, green: 0.48, blue: 0.24)
    static let red = Color(red: 0.898, green: 0.282, blue: 0.302)
    static let water = Color(red: 0.25, green: 0.7, blue: 1.0)
    static let purple = Color(red: 0.61, green: 0.48, blue: 1.0)
    static let sleep = Color(red: 0.79, green: 0.8, blue: 0.83)

    static let spring = Animation.spring(response: 0.55, dampingFraction: 0.82)
}

// MARK: Card

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ c: () -> Content) { content = c() }
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct Label2: View {
    let t: String
    var body: some View { Text(t).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.muted) }
}

/// Small rounded icon used on cards and lists.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct ScreenTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let s = subtitle { Text(s).font(.system(size: 13)).foregroundColor(Theme.muted) }
            Text(title).font(.system(size: 30, weight: .bold)).foregroundColor(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appear(0)
    }
}

// MARK: Appear animation (slide up + fade, staggered)

struct AppearModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 24)
            .scaleEffect(shown ? 1 : 0.97)
            .onAppear {
                withAnimation(Theme.spring.delay(Double(index) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func appear(_ index: Int) -> some View { modifier(AppearModifier(index: index)) }
}

// MARK: Button press bounce

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct BigButton: View {
    let title: String
    let symbol: String
    var color: Color = .white
    var textColor: Color = .black
    let action: () -> Void
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(color)
            .foregroundColor(textColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: Animated ring

struct Ring: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 8
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(shown, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.4), radius: 6)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.2).delay(0.15)) { shown = clamp(fraction) } }
        .onChange(of: fraction) { f in withAnimation(.easeInOut(duration: 0.6)) { shown = clamp(f) } }
    }

    func clamp(_ v: Double) -> Double { max(0, min(1, v.isFinite ? v : 0)) }
}

struct Dial: View {
    let value: String
    let label: String
    let fraction: Double
    let color: Color
    var size: CGFloat = 96
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Ring(fraction: fraction, color: color, lineWidth: 8)
                Text(value)
                    .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Theme.text)
                    .contentTransition(.numericText())
            }
            .frame(width: size, height: size)
            Label2(t: label)
        }
    }
}

// MARK: Counting number

struct CountText: View {
    let value: Double
    var decimals: Int = 0
    var size: CGFloat = 24
    var color: Color = Theme.text
    @State private var shown = 0.0

    var body: some View {
        Text(decimals == 0 ? "\(Int(shown.rounded()))" : String(format: "%.\(decimals)f", shown))
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(color)
            .contentTransition(.numericText())
            .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.2)) { shown = value } }
            .onChange(of: value) { v in withAnimation(.easeOut(duration: 0.4)) { shown = v } }
    }
}

// MARK: Pulsing heart

struct PulsingHeart: View {
    let bpm: Int?
    var size: CGFloat = 18
    @State private var beat = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundColor(Theme.red)
            .scaleEffect(beat ? 1.22 : 1)
            .animation(.easeOut(duration: interval * 0.35), value: beat)
            .task(id: bpm ?? 0) {
                while !Task.isCancelled {
                    if bpm != nil {
                        beat = true
                        try? await Task.sleep(nanoseconds: UInt64(interval * 0.35 * 1_000_000_000))
                        beat = false
                        try? await Task.sleep(nanoseconds: UInt64(interval * 0.65 * 1_000_000_000))
                    } else {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }
    }

    var interval: Double { 60.0 / Double(max(40, min(200, bpm ?? 70))) }
}

// MARK: Sparkline (draws itself)

struct Sparkline: View {
    let values: [Int]
    let color: Color
    var height: CGFloat = 44
    @State private var drawn: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            if values.count > 1, let lo = values.min(), let hi = values.max() {
                let span = max(Double(hi - lo), 1)
                let path = Path { p in
                    for (i, v) in values.enumerated() {
                        let x = g.size.width * Double(i) / Double(values.count - 1)
                        let y = 4 + (g.size.height - 8) * (1 - Double(v - lo) / span)
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                path.trim(from: 0, to: drawn)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .shadow(color: color.opacity(0.5), radius: 4)
            } else {
                HStack(spacing: 6) {
                    ProgressView().tint(Theme.muted).scaleEffect(0.8)
                    Text("Waiting for your band…").font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 1.1).delay(0.2)) { drawn = 1 } }
    }
}

// MARK: Zone bars (grow in)

let zoneColors: [Color] = [Theme.blue, Theme.green, Theme.amber, Theme.orange, Theme.red]

struct ZoneBars: View {
    let seconds: [Double]
    @State private var grow = false

    var body: some View {
        let total = max(seconds.reduce(0, +), 1)
        VStack(spacing: 8) {
            ForEach(Array((0..<5).reversed()), id: \.self) { i in
                HStack(spacing: 10) {
                    Text("Zone \(i + 1)").font(.system(size: 12)).foregroundColor(Theme.muted).frame(width: 50, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule().fill(zoneColors[i])
                                .frame(width: grow ? max(6, g.size.width * seconds[i] / total) : 0)
                        }
                    }
                    .frame(height: 7)
                    Text(fmtDuration(seconds[i])).font(.system(size: 12, design: .rounded)).monospacedDigit()
                        .foregroundColor(Theme.text).frame(width: 52, alignment: .trailing)
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.25)) { grow = true } }
    }
}

// MARK: Water wave

struct WaveShape: Shape {
    var level: Double      // 0...1 how full
    var phase: Double      // moves the wave
    var amplitude: Double = 8

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, phase) }
        set { level = newValue.first; phase = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let y0 = r.height * (1 - max(0, min(1, level)))
        p.move(to: CGPoint(x: 0, y: r.height))
        p.addLine(to: CGPoint(x: 0, y: y0))
        var x: CGFloat = 0
        while x <= r.width {
            let rel = Double(x / max(r.width, 1))
            let y = y0 + CGFloat(sin(rel * 2 * .pi * 1.4 + phase) * amplitude)
            p.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        p.addLine(to: CGPoint(x: r.width, y: r.height))
        p.closeSubpath()
        return p
    }
}

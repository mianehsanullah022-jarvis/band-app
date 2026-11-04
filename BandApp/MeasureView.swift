import SwiftUI
import Charts

// MARK: Measure hub

struct MeasureView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ScreenTitle(title: "Measure", subtitle: "Tap one to start")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        NavigationLink { HRMeasureView() } label: {
                            tile("Heart rate", "heart.fill", Theme.red,
                                 ble.heartRate.map { "\($0) bpm" } ?? (store.hrChecks.last.map { "\($0.bpm) bpm" } ?? "Measure"))
                        }
                        .buttonStyle(PressStyle()).appear(1)

                        NavigationLink { RhythmView() } label: {
                            tile("Heart rhythm", "waveform.path.ecg", Theme.green, ble.heartRate == nil ? "Live wave" : "Live now")
                        }
                        .buttonStyle(PressStyle()).appear(2)

                        NavigationLink { BPView() } label: {
                            tile("Blood pressure", "drop.fill", Theme.purple,
                                 store.bp.last.map { "\($0.systolic)/\($0.diastolic)" } ?? "Add reading")
                        }
                        .buttonStyle(PressStyle()).appear(3)

                        NavigationLink { WaterView() } label: {
                            tile("Water", "drop.circle.fill", Theme.water,
                                 String(format: "%.1f / %.1f L", Double(store.waterToday) / 1000, Double(store.profile.waterGoalMl) / 1000))
                        }
                        .buttonStyle(PressStyle()).appear(4)
                    }

                    if !store.hrChecks.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Label2(t: "Recent heart rate checks")
                                ForEach(store.hrChecks.suffix(5).reversed()) { c in
                                    HStack {
                                        Image(systemName: "heart.fill").foregroundColor(Theme.red).font(.system(size: 12))
                                        Text("\(c.bpm) bpm").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                                        Text("\(c.low)–\(c.high)").font(.system(size: 12)).foregroundColor(Theme.muted)
                                        Spacer()
                                        Text(c.date, format: .dateTime.day().month().hour().minute())
                                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                                    }
                                }
                            }
                        }
                        .appear(5)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    func tile(_ title: String, _ symbol: String, _ color: Color, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            IconBadge(symbol: symbol, color: color, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                Text(value).font(.system(size: 13)).foregroundColor(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(
            ZStack {
                Theme.card
                LinearGradient(colors: [color.opacity(0.14), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: Heart rate (30 second check)

struct HRMeasureView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: Store
    @State private var measuring = false
    @State private var start = Date()
    @State private var values: [Int] = []
    @State private var result: HRCheck?
    let length: Double = 30

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                    let elapsed = measuring ? min(length, ctx.date.timeIntervalSince(start)) : 0
                    ZStack {
                        Circle().stroke(Theme.line, lineWidth: 14)
                        Circle().trim(from: 0, to: measuring ? elapsed / length : (result == nil ? 0 : 1))
                            .stroke(Theme.red, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Theme.red.opacity(0.5), radius: 8)
                        VStack(spacing: 6) {
                            PulsingHeart(bpm: ble.heartRate, size: 34)
                            Text(display)
                                .font(.system(size: 54, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(Theme.text)
                                .contentTransition(.numericText())
                            Text(measuring ? "\(Int(length - elapsed)) sec left" : "bpm")
                                .font(.system(size: 14)).foregroundColor(Theme.muted)
                        }
                    }
                    .frame(width: 240, height: 240)
                    .onChange(of: elapsed >= length) { finished in if finished && measuring { finish() } }
                }
                .padding(.top, 10)
                .appear(0)

                if ble.connected == nil {
                    Text("Connect your band first: More → Connect band.")
                        .font(.system(size: 14)).foregroundColor(Theme.amber).multilineTextAlignment(.center)
                } else if ble.heartRate == nil {
                    Text("Your band hasn't sent heart rate yet. Keep it snug on your wrist.")
                        .font(.system(size: 14)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
                }

                if let r = result, !measuring {
                    Card {
                        HStack {
                            stat("Average", r.bpm)
                            stat("Lowest", r.low)
                            stat("Highest", r.high)
                        }
                    }
                    .appear(1)
                }

                if measuring {
                    BigButton(title: "Stop", symbol: "stop.fill", color: Theme.card, textColor: Theme.text) { measuring = false }
                } else {
                    BigButton(title: result == nil ? "Start 30-second check" : "Measure again", symbol: "heart.fill",
                              color: Theme.red, textColor: .white) {
                        values = []
                        result = nil
                        start = Date()
                        withAnimation { measuring = true }
                    }
                    .disabled(ble.heartRate == nil)
                    .opacity(ble.heartRate == nil ? 0.5 : 1)
                }

                Text("Sit still and breathe normally while measuring.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Heart rate")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: ble.heartRate) { v in
            if measuring, let v = v { values.append(v) }
        }
    }

    var display: String {
        if let r = result, !measuring { return "\(r.bpm)" }
        return ble.heartRate.map { "\($0)" } ?? "--"
    }

    func finish() {
        measuring = false
        guard !values.isEmpty else { return }
        let c = HRCheck(date: Date(), bpm: values.reduce(0, +) / values.count, low: values.min() ?? 0, high: values.max() ?? 0)
        store.addHRCheck(c)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(Theme.spring) { result = c }
    }

    func stat(_ t: String, _ v: Int) -> some View {
        VStack(spacing: 4) {
            Label2(t: t)
            CountText(value: Double(v), size: 24)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Heart rhythm (animated wave from real heart rate)

struct RhythmView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var startTime = Date()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    PulsingHeart(bpm: ble.heartRate, size: 22)
                    Text(ble.heartRate.map { "\($0)" } ?? "--")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Theme.text)
                        .contentTransition(.numericText())
                        .animation(.easeOut, value: ble.heartRate)
                    Text("bpm").foregroundColor(Theme.muted)
                    Spacer()
                }
                .appear(0)

                TimelineView(.animation) { ctx in
                    Canvas { g, size in
                        drawGrid(g, size)
                        guard let bpm = ble.heartRate else { return }
                        let t = ctx.date.timeIntervalSince(startTime)
                        let beat = 60.0 / Double(bpm)
                        let secondsOnScreen = 4.0
                        var path = Path()
                        let steps = Int(size.width / 2)
                        for i in 0...steps {
                            let x = Double(i) * 2
                            let time = t - secondsOnScreen + x / size.width * secondsOnScreen
                            let phase = time.truncatingRemainder(dividingBy: beat) / beat
                            let y = size.height / 2 - wave(phase < 0 ? phase + 1 : phase) * size.height * 0.38
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        g.addFilter(.shadow(color: Theme.green.opacity(0.7), radius: 5))
                        g.stroke(path, with: .color(Theme.green), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(height: 220)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if ble.heartRate == nil {
                        Text(ble.connected == nil ? "Connect your band to see your heartbeat" : "Waiting for your heartbeat…")
                            .font(.system(size: 14)).foregroundColor(Theme.muted)
                    }
                }
                .appear(1)

                Card {
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(symbol: "info.circle.fill", color: Theme.muted)
                        Text("This wave is drawn live from your band's heart rate, so it beats at your real speed. It is not a medical ECG.")
                            .font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.8))
                    }
                }
                .appear(2)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Heart rhythm")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A heartbeat shape (P, QRS and T waves) for one beat. phase is 0...1.
    func wave(_ p: Double) -> Double {
        func bump(_ c: Double, _ w: Double, _ h: Double) -> Double { h * exp(-pow((p - c) / w, 2)) }
        return bump(0.18, 0.035, 0.12) - bump(0.30, 0.008, 0.18) + bump(0.32, 0.012, 1.0)
            - bump(0.345, 0.01, 0.3) + bump(0.55, 0.05, 0.25)
    }

    func drawGrid(_ g: GraphicsContext, _ size: CGSize) {
        var grid = Path()
        var x: CGFloat = 0
        while x < size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += 20 }
        var y: CGFloat = 0
        while y < size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += 20 }
        g.stroke(grid, with: .color(Theme.line.opacity(0.7)), lineWidth: 0.5)
    }
}

// MARK: Blood pressure log

struct BPView: View {
    @EnvironmentObject var store: Store
    @State private var sys = 120
    @State private var dia = 80
    @State private var pulse = 72
    @State private var justSaved: BPReading?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            IconBadge(symbol: "drop.fill", color: Theme.purple)
                            Label2(t: "New reading from your BP machine")
                        }
                        HStack(spacing: 10) {
                            picker("Upper", $sys, 70...250)
                            Text("/").font(.system(size: 28, weight: .bold)).foregroundColor(Theme.muted)
                            picker("Lower", $dia, 40...150)
                            picker("Pulse", $pulse, 30...200)
                        }
                        let cat = BPCategory(sys: sys, dia: dia)
                        HStack {
                            Circle().fill(cat.color).frame(width: 10, height: 10)
                            Text(cat.title).font(.system(size: 14, weight: .semibold)).foregroundColor(cat.color)
                                .animation(.easeInOut, value: cat.title)
                        }
                        BigButton(title: "Save reading", symbol: "checkmark", color: Theme.purple, textColor: .white) {
                            let r = BPReading(date: Date(), systolic: sys, diastolic: dia, pulse: pulse)
                            withAnimation(Theme.spring) {
                                store.addBP(r)
                                justSaved = r
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                }
                .appear(0)

                if let r = justSaved, BPCategory(sys: r.systolic, dia: r.diastolic) == .crisis {
                    Card {
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(symbol: "exclamationmark.triangle.fill", color: Theme.red)
                            Text("This reading is very high. Rest 5 minutes and measure again. If it stays this high, or you feel chest pain, short of breath or dizzy, get medical help right away.")
                                .font(.system(size: 13)).foregroundColor(Theme.text)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                if store.bp.count >= 2 {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label2(t: "Your trend")
                            Chart {
                                ForEach(store.bp.suffix(20)) { r in
                                    LineMark(x: .value("Date", r.date), y: .value("mmHg", r.systolic), series: .value("Type", "Upper"))
                                        .foregroundStyle(Theme.purple)
                                        .symbol(.circle)
                                    LineMark(x: .value("Date", r.date), y: .value("mmHg", r.diastolic), series: .value("Type", "Lower"))
                                        .foregroundStyle(Theme.water)
                                        .symbol(.circle)
                                }
                            }
                            .chartYScale(domain: 40...200)
                            .frame(height: 180)
                        }
                    }
                    .appear(1)
                }

                if !store.bp.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label2(t: "History")
                            ForEach(store.bp.reversed()) { r in
                                let cat = BPCategory(sys: r.systolic, dia: r.diastolic)
                                HStack {
                                    Text("\(r.systolic)/\(r.diastolic)").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                                    if let p = r.pulse { Text("♥ \(p)").font(.system(size: 12)).foregroundColor(Theme.muted) }
                                    Text(cat.title).font(.system(size: 11, weight: .medium)).foregroundColor(cat.color)
                                    Spacer()
                                    Text(r.date, format: .dateTime.day().month().hour().minute()).font(.system(size: 12)).foregroundColor(Theme.muted)
                                    Button { withAnimation { store.deleteBP(r.id) } } label: {
                                        Image(systemName: "trash").font(.system(size: 13)).foregroundColor(Theme.muted)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Delete reading")
                                }
                            }
                        }
                    }
                    .appear(2)
                }

                Text("Your band can't measure blood pressure. Use a real BP machine, then save the numbers here to track them.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Blood pressure")
        .navigationBarTitleDisplayMode(.inline)
    }

    func picker(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        VStack(spacing: 2) {
            Label2(t: title)
            Picker(title, selection: value) {
                ForEach(Array(range), id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
            .clipped()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Water

struct WaterView: View {
    @EnvironmentObject var store: Store
    @State private var phase = 0.0
    @State private var shownLevel = 0.0

    var level: Double { Double(store.waterToday) / Double(max(store.profile.waterGoalMl, 1)) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Theme.card)
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        ZStack {
                            WaveShape(level: shownLevel, phase: t * 2.2 + 1.5, amplitude: 7)
                                .fill(Theme.water.opacity(0.35))
                            WaveShape(level: shownLevel, phase: t * 3, amplitude: 9)
                                .fill(LinearGradient(colors: [Theme.water, Theme.blue], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    RoundedRectangle(cornerRadius: 40, style: .continuous).stroke(Theme.line, lineWidth: 2)
                    VStack(spacing: 4) {
                        Text(String(format: "%.2f L", Double(store.waterToday) / 1000))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundColor(.white)
                        Text("of \(String(format: "%.1f", Double(store.profile.waterGoalMl) / 1000)) L goal · \(Int(min(level, 9.99) * 100))%")
                            .font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.85))
                    }
                    .shadow(color: .black.opacity(0.4), radius: 4)
                }
                .frame(width: 220, height: 300)
                .appear(0)

                HStack(spacing: 12) {
                    waterButton("−", -store.profile.glassMl, Theme.card, Theme.text)
                    waterButton("+ Glass \(store.profile.glassMl) ml", store.profile.glassMl, Theme.water, .black)
                    waterButton("+500", 500, Theme.card, Theme.text)
                }
                .appear(1)

                if level >= 1 {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(Theme.green)
                        Text("Goal reached. Great job!").foregroundColor(Theme.green).font(.system(size: 15, weight: .semibold))
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label2(t: "This week")
                        Chart {
                            ForEach(store.waterWeek) { d in
                                BarMark(x: .value("Day", "\(d.index)\(d.label)"), y: .value("Litres", Double(d.ml) / 1000))
                                    .foregroundStyle(d.ml >= store.profile.waterGoalMl ? Theme.green : Theme.water)
                                    .cornerRadius(5)
                            }
                            RuleMark(y: .value("Goal", Double(store.profile.waterGoalMl) / 1000))
                                .foregroundStyle(Theme.muted)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        .chartXAxis {
                            AxisMarks { v in
                                AxisValueLabel {
                                    if let s = v.as(String.self) { Text(String(s.dropFirst())) }
                                }
                            }
                        }
                        .frame(height: 150)
                    }
                }
                .appear(2)

                Text("Your band can't measure water in your body, so tap each time you drink.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Water")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { withAnimation(.spring(response: 1.2, dampingFraction: 0.75).delay(0.2)) { shownLevel = min(level, 1) } }
        .onChange(of: store.waterToday) { _ in withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { shownLevel = min(level, 1) } }
    }

    func waterButton(_ title: String, _ ml: Int, _ bg: Color, _ fg: Color) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(Theme.spring) { store.addWater(ml) }
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(bg)
                .foregroundColor(fg)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

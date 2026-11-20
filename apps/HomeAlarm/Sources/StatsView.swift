import SwiftUI
import Charts
import AlarmCore

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var period: StatsPeriod = .month
    @State private var houseFilter: UUID?

    var body: some View {
        let stats = AlarmStats(data: model.data, houseID: houseFilter, period: period)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Periodo", selection: $period) {
                    ForEach(StatsPeriod.allCases) { p in Text(p.label).tag(p) }
                }
                .pickerStyle(.segmented)

                if model.houses.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip(title: "Tutte", selected: houseFilter == nil) { houseFilter = nil }
                            ForEach(model.houses) { h in
                                Chip(title: h.name, icon: h.icon, selected: houseFilter == h.id) { houseFilter = h.id }
                            }
                        }
                    }
                }

                if stats.isEmpty {
                    EmptyStateView(icon: "chart.bar.xaxis", title: "Ancora nessun dato",
                                   message: "Le statistiche si riempiono man mano che invii comandi alla centralina.")
                } else {
                    protectionCard(stats)
                    kpiGrid(stats)
                    activityCard(stats)
                    if !stats.zones.isEmpty { zonesCard(stats) }
                    hoursCard(stats)
                    weekdayCard(stats)
                    if !stats.sources.isEmpty { sourcesCard(stats) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(m3.surface)
        .navigationTitle("Statistiche")
    }

    // MARK: Cards

    private func protectionCard(_ s: AlarmStats) -> some View {
        M3Card(color: m3.primaryContainer, padding: 20) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(m3.onPrimaryContainer.opacity(0.12), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: s.protectedShare)
                        .stroke(m3.primary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(AlarmFormat.percent(s.protectedShare))
                        .font(.m3TitleLarge)
                        .foregroundStyle(m3.onPrimaryContainer)
                        .monospacedDigit()
                }
                .frame(width: 96, height: 96)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: s.protectedShare)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tempo protetto")
                        .font(.m3LabelLarge)
                        .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                    Text(AlarmFormat.duration(s.protectedTime))
                        .font(.m3HeadlineMedium)
                        .foregroundStyle(m3.onPrimaryContainer)
                    Text(insight(s))
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func insight(_ s: AlarmStats) -> String {
        switch (s.typicalArmHour, s.typicalDisarmHour) {
        case let (a?, d?): return "Di solito inserisci alle \(AlarmFormat.hour(a)) e disinserisci alle \(AlarmFormat.hour(d))."
        case let (a?, nil): return "Di solito inserisci verso le \(AlarmFormat.hour(a))."
        case let (nil, d?): return "Di solito disinserisci verso le \(AlarmFormat.hour(d))."
        default: return "Stimato dagli SMS di inserimento e disinserimento."
        }
    }

    private func kpiGrid(_ s: AlarmStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            KPITile(title: "SMS inviati", value: "\(s.sent)", icon: "paperplane.fill", tones: m3.primaryTones,
                    footnote: s.successRate.map { "\(AlarmFormat.percent($0)) completati" })
            KPITile(title: "Inserimenti", value: "\(s.arms)", icon: "lock.shield.fill", tones: m3.armed,
                    footnote: s.averageArmDuration.map { "media \(AlarmFormat.duration($0))" })
            KPITile(title: "Disinserimenti", value: "\(s.disarms)", icon: "shield.slash.fill", tones: m3.danger,
                    footnote: s.statusRequests > 0 ? "\(s.statusRequests) richieste stato" : nil)
            KPITile(title: "Serie attuale", value: "\(s.currentStreak) g", icon: "flame.fill", tones: m3.tertiaryTones,
                    footnote: "record \(s.longestStreak) g")
            KPITile(title: "Inserimento più lungo", value: s.longestArmDuration.map(AlarmFormat.duration) ?? "–",
                    icon: "hourglass", tones: m3.neutral, footnote: nil)
            KPITile(title: "Giorni attivi", value: "\(s.activeDays)", icon: "calendar", tones: m3.neutral,
                    footnote: s.cancelled + s.failed > 0 ? "\(s.cancelled) annullati · \(s.failed) falliti" : nil)
        }
    }

    private func activityCard(_ s: AlarmStats) -> some View {
        let unit: Calendar.Component = s.bucketUnit.calendarComponent
        let caption: String = {
            switch s.bucketUnit {
            case .day: return "per giorno"
            case .week: return "per settimana"
            case .month: return "per mese"
            }
        }()
        return ChartCard(title: "Attività", subtitle: caption) {
            Chart {
                ForEach(s.buckets) { b in
                    BarMark(x: .value("Periodo", b.start, unit: unit), y: .value("Comandi", b.arms))
                        .foregroundStyle(by: .value("Tipo", "Inserimenti"))
                        .cornerRadius(4)
                    BarMark(x: .value("Periodo", b.start, unit: unit), y: .value("Comandi", b.disarms))
                        .foregroundStyle(by: .value("Tipo", "Disinserimenti"))
                        .cornerRadius(4)
                    if b.status > 0 {
                        BarMark(x: .value("Periodo", b.start, unit: unit), y: .value("Comandi", b.status))
                            .foregroundStyle(by: .value("Tipo", "Stato"))
                            .cornerRadius(4)
                    }
                }
            }
            .chartForegroundStyleScale([
                "Inserimenti": m3.success,
                "Disinserimenti": m3.error,
                "Stato": m3.tertiary
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(m3.outlineVariant)
                    AxisValueLabel().foregroundStyle(m3.onSurfaceVariant)
                }
            }
            .frame(height: 200)
        }
    }

    private func zonesCard(_ s: AlarmStats) -> some View {
        ChartCard(title: "Zone", subtitle: "inserimenti e tempo") {
            VStack(spacing: 16) {
                if s.zones.contains(where: { $0.count > 0 }) {
                    Chart(s.zones.filter { $0.count > 0 }) { z in
                        SectorMark(angle: .value("Volte", z.count), innerRadius: .ratio(0.62), angularInset: 2)
                            .foregroundStyle(m3.tones(z.colorHex).accent)
                            .cornerRadius(6)
                    }
                    .frame(height: 170)
                }
                VStack(spacing: 10) {
                    ForEach(s.zones) { z in
                        HStack(spacing: 12) {
                            IconBadge(icon: z.icon, tones: m3.tones(z.colorHex), size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(z.name)
                                    .font(.m3TitleSmall)
                                    .foregroundStyle(m3.onSurface)
                                Text("\(AlarmFormat.duration(z.armedTime)) inserita")
                                    .font(.m3BodySmall)
                                    .foregroundStyle(m3.onSurfaceVariant)
                            }
                            Spacer()
                            Text("\(z.count)×")
                                .font(.m3TitleMedium)
                                .foregroundStyle(m3.onSurface)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func hoursCard(_ s: AlarmStats) -> some View {
        ChartCard(title: "Orari", subtitle: "a che ora invii i comandi") {
            Chart {
                ForEach(0..<24, id: \.self) { h in
                    BarMark(x: .value("Ora", h), y: .value("Inserimenti", s.armsByHour[h]))
                        .foregroundStyle(by: .value("Tipo", "Inserimenti"))
                        .position(by: .value("Tipo", "Inserimenti"))
                    BarMark(x: .value("Ora", h), y: .value("Disinserimenti", s.disarmsByHour[h]))
                        .foregroundStyle(by: .value("Tipo", "Disinserimenti"))
                        .position(by: .value("Tipo", "Disinserimenti"))
                }
            }
            .chartForegroundStyleScale(["Inserimenti": m3.success, "Disinserimenti": m3.error])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    AxisValueLabel {
                        if let h = v.as(Int.self) { Text("\(h)") }
                    }
                    .foregroundStyle(m3.onSurfaceVariant)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(m3.outlineVariant)
                    AxisValueLabel().foregroundStyle(m3.onSurfaceVariant)
                }
            }
            .frame(height: 170)
        }
    }

    private func weekdayCard(_ s: AlarmStats) -> some View {
        ChartCard(title: "Giorni della settimana", subtitle: "comandi inviati") {
            Chart {
                ForEach(0..<7, id: \.self) { i in
                    BarMark(x: .value("Giorno", AlarmStats.weekdaySymbols[i]), y: .value("Comandi", s.byWeekday[i]))
                        .foregroundStyle(m3.primary.gradient)
                        .cornerRadius(6)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(m3.outlineVariant)
                    AxisValueLabel().foregroundStyle(m3.onSurfaceVariant)
                }
            }
            .frame(height: 150)
        }
    }

    private func sourcesCard(_ s: AlarmStats) -> some View {
        let total = max(1, s.sources.reduce(0) { $0 + $1.count })
        return ChartCard(title: "Da dove", subtitle: "app, widget, controlli, Siri") {
            VStack(spacing: 12) {
                ForEach(s.sources) { src in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(src.source.label)
                                .font(.m3LabelLarge)
                                .foregroundStyle(m3.onSurface)
                            Spacer()
                            Text("\(src.count)")
                                .font(.m3LabelLarge)
                                .foregroundStyle(m3.onSurfaceVariant)
                                .monospacedDigit()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(m3.surfaceContainerHighest)
                                Capsule().fill(m3.primary)
                                    .frame(width: max(8, geo.size.width * CGFloat(src.count) / CGFloat(total)))
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct KPITile: View {
    @Environment(\.m3) private var m3
    let title: String
    let value: String
    let icon: String
    let tones: Tones
    let footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(icon: icon, tones: tones, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.m3HeadlineSmall)
                    .foregroundStyle(m3.onSurface)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.m3LabelMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
                Text(footnote ?? " ")
                    .font(.m3LabelSmall)
                    .foregroundStyle(m3.outline)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ChartCard<Content: View>: View {
    @Environment(\.m3) private var m3
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        M3Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.m3TitleMedium)
                        .foregroundStyle(m3.onSurface)
                    Text(subtitle)
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                content
            }
        }
    }
}

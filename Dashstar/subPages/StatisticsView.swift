import Charts
import SwiftUI

private struct TrafficSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let directUpload: Double
    let directDownload: Double
    let proxyUpload: Double
    let proxyDownload: Double
    let overallUpload: Double
    let overallDownload: Double

    var directTotal: Double { directUpload + directDownload }
    var proxyTotal: Double { proxyUpload + proxyDownload }
    var overallTotal: Double { overallUpload + overallDownload }
}

private enum TrafficSeries: String, CaseIterable, Identifiable {
    case directUpload = "Direct Upload"
    case directDownload = "Direct Download"
    case directTotal = "Direct Total"
    case proxyUpload = "Proxy Upload"
    case proxyDownload = "Proxy Download"
    case proxyTotal = "Proxy Total"
    case overallTotal = "Overall Total"

    var id: Self { self }

    var color: Color {
        switch self {
        case .directUpload: .cyan
        case .directDownload: .mint
        case .directTotal: .green
        case .proxyUpload: .purple
        case .proxyDownload: .pink
        case .proxyTotal: .red
        case .overallTotal: .orange
        }
    }

    func value(in sample: TrafficSample) -> Double {
        switch self {
        case .directUpload: sample.directUpload
        case .directDownload: sample.directDownload
        case .directTotal: sample.directTotal
        case .proxyUpload: sample.proxyUpload
        case .proxyDownload: sample.proxyDownload
        case .proxyTotal: sample.proxyTotal
        case .overallTotal: sample.overallTotal
        }
    }
}

private struct TrafficSeriesPoint: Identifiable {
    let id: String
    let timestamp: Date
    let value: Double
    let series: TrafficSeries
}

struct StatisticsView: View {
    @Environment(TunnelController.self) private var tunnel
    @Environment(StatisticsPiPController.self) private var statisticsPiP
    @State private var samples: [TrafficSample] = []
    @State private var previousTotals: TunnelTrafficTotals?
    @State private var previousDate: Date?
    @State private var visibleSeries = Set(TrafficSeries.allCases)
    @State private var selectedDate: Date?
    @State private var connectedAt: Date?
    @State private var currentDate = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) { trafficCard }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .task { await monitorTraffic() }
        }
    }

    private var trafficCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Real-time Traffic").font(.headline)
                    Text(LocalizedStringKey(
                        tunnel.isConnected ? "Bytes per second" : "Connect VPN to view live traffic"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(tunnel.isConnected ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 16) {
                metric("Direct", value: samples.last?.directTotal ?? 0, color: .green)
                metric("Proxy", value: samples.last?.proxyTotal ?? 0, color: .red)
                metric("Overall", value: samples.last?.overallTotal ?? 0, color: .orange)
            }

            Toggle(isOn: pictureInPictureBinding) {
                Label("Picture in Picture", systemImage: "pip")
            }
            .disabled(!tunnel.isConnected && !statisticsPiP.isActive)

            if let error = statisticsPiP.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Label("Connection Duration", systemImage: "clock")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(connectionDuration)
                    .font(.body.monospacedDigit().weight(.semibold))
            }

            Chart {
                ForEach(chartPoints) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Bytes/s", point.value),
                        series: .value("Traffic", point.series.rawValue)
                    )
                    .foregroundStyle(by: .value("Traffic", point.series.rawValue))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: point.series == .overallTotal ? 2.8 : 1.8))
                }

                if let selectedSample {
                    RuleMark(x: .value("Selected time", selectedSample.timestamp))
                        .foregroundStyle(.secondary.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            trafficTooltip(selectedSample)
                        }
                }
            }
            .chartForegroundStyleScale(seriesColors)
            .chartLegend(position: .bottom, alignment: .leading, spacing: 18)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                    AxisValueLabel {
                        if let rate = value.as(Double.self) { Text(shortRate(rate)) }
                    }
                }
            }
            .chartYScale(domain: 0...chartMaximum)
            .chartXSelection(value: $selectedDate)
            .frame(height: 300)

            Divider().padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text("Visible Lines")
                    .font(.subheadline.weight(.semibold))
                ForEach(TrafficSeries.allCases) { series in
                    Toggle(isOn: visibilityBinding(for: series)) {
                        HStack(spacing: 8) {
                            Circle().fill(series.color).frame(width: 8, height: 8)
                            Text(LocalizedStringKey(series.rawValue))
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .compatibleGlassSurface(cornerRadius: 30)
    }

    private var chartPoints: [TrafficSeriesPoint] {
        samples.flatMap { sample in
            TrafficSeries.allCases.compactMap { series in
                guard visibleSeries.contains(series) else { return nil }
                return TrafficSeriesPoint(
                    id: "\(series.rawValue)-\(sample.id)",
                    timestamp: sample.timestamp,
                    value: series.value(in: sample),
                    series: series
                )
            }
        }
    }

    private var pictureInPictureBinding: Binding<Bool> {
        Binding(
            get: { statisticsPiP.isActive },
            set: { enabled in
                if enabled { statisticsPiP.start(tunnel: tunnel) }
                else { statisticsPiP.stop() }
            }
        )
    }

    private var seriesColors: KeyValuePairs<String, Color> {
        [
            TrafficSeries.directUpload.rawValue: .cyan,
            TrafficSeries.directDownload.rawValue: .mint,
            TrafficSeries.directTotal.rawValue: .green,
            TrafficSeries.proxyUpload.rawValue: .purple,
            TrafficSeries.proxyDownload.rawValue: .pink,
            TrafficSeries.proxyTotal.rawValue: .red,
            TrafficSeries.overallTotal.rawValue: .orange,
        ]
    }

    private var chartMaximum: Double {
        let values = samples.flatMap { sample in
            TrafficSeries.allCases.compactMap { visibleSeries.contains($0) ? $0.value(in: sample) : nil }
        }
        return max(1_024, (values.max() ?? 0) * 1.15)
    }

    private var selectedSample: TrafficSample? {
        guard let selectedDate else { return nil }
        return samples.min {
            abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate))
        }
    }

    private var connectionDuration: String {
        guard tunnel.isConnected, let connectedAt else { return "00:00:00" }
        let seconds = max(0, Int(currentDate.timeIntervalSince(connectedAt)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    private func trafficTooltip(_ sample: TrafficSample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sample.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption2.monospacedDigit().weight(.semibold))
            ForEach(TrafficSeries.allCases.filter { visibleSeries.contains($0) }) { series in
                HStack(spacing: 5) {
                    Circle().fill(series.color).frame(width: 6, height: 6)
                    Text(series.rawValue)
                    Spacer(minLength: 8)
                    Text(rateText(series.value(in: sample)))
                        .monospacedDigit()
                }
                .font(.caption2)
            }
        }
        .padding(9)
        .frame(width: 190)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }

    private func visibilityBinding(for series: TrafficSeries) -> Binding<Bool> {
        Binding(
            get: { visibleSeries.contains(series) },
            set: { isVisible in
                if isVisible { visibleSeries.insert(series) }
                else { visibleSeries.remove(series) }
            }
        )
    }

    private func metric(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(color)
            Text(rateText(value))
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monitorTraffic() async {
        while !Task.isCancelled {
            let now = Date()
            currentDate = now
            do {
                if let totals = try await tunnel.trafficTotals() {
                    connectedAt = totals.connectedAt
                    if let previousTotals, let previousDate {
                        let interval = max(now.timeIntervalSince(previousDate), 0.1)
                        func rate(_ current: Int64, _ previous: Int64) -> Double {
                            Double(max(0, current - previous)) / interval
                        }
                        samples.append(TrafficSample(
                            timestamp: now,
                            directUpload: rate(totals.directUpload, previousTotals.directUpload),
                            directDownload: rate(totals.directDownload, previousTotals.directDownload),
                            proxyUpload: rate(totals.proxyUpload, previousTotals.proxyUpload),
                            proxyDownload: rate(totals.proxyDownload, previousTotals.proxyDownload),
                            overallUpload: rate(totals.upload, previousTotals.upload),
                            overallDownload: rate(totals.download, previousTotals.download)
                        ))
                        if samples.count > 60 { samples.removeFirst(samples.count - 60) }
                    }
                    previousTotals = totals
                    previousDate = now
                } else {
                    connectedAt = nil
                    previousTotals = nil
                    previousDate = nil
                }
            } catch {
                connectedAt = nil
                previousTotals = nil
                previousDate = nil
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func rateText(_ value: Double) -> String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary))/s"
    }

    private func shortRate(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }
}

#Preview {
    StatisticsView()
        .environment(TunnelController())
        .environment(StatisticsPiPController())
}

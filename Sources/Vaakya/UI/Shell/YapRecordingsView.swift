import SwiftUI
import VaakyaCore

/// Full-width recordings library — big section titles, dense-but-airy rows, hover motion.
struct YapRecordingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable private var router = ShellRouter.shared
    @State private var filter = ""
    @State private var searchFocused = false

    private var jobs: [TranscriptionJobRecord] {
        let all = env.transcriptionRunner.jobs
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.sourceName.lowercased().contains(q)
            || ($0.finalText ?? $0.rawText ?? "").lowercased().contains(q)
        }
    }

    private var sections: [(String, [TranscriptionJobRecord])] {
        let cal = Calendar.current
        let now = Date()
        var buckets: [String: [TranscriptionJobRecord]] = [:]
        var order: [String] = []

        for job in jobs {
            let key = sectionKey(for: job, now: now, calendar: cal)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(job)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(YapTheme.hairline).frame(height: 1)

            if jobs.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(sections, id: \.0) { title, items in
                            sectionBlock(title: title, items: items)
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 28)
                }
            }
        }
        .background(YapTheme.canvas)
        .onAppear { env.transcriptionRunner.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                YapBreadcrumb(crumbs: [
                    ("vaakya", { router.popToRoot() }),
                    ("recordings", nil),
                ])
                Text("\(jobs.count) RECORDING\(jobs.count == 1 ? "" : "S")")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .contentTransition(.numericText())
            }
            Spacer()
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.primary.opacity(0.4))
                    TextField("Find in recordings", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .frame(minWidth: 160, idealWidth: 200)
                    if !filter.isEmpty {
                        Button {
                            filter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(searchFocused ? 0.35 : 0.18), lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                )
                .onHover { searchFocused = $0 }

                YapPillButton(title: "start recording", systemImage: "record.circle", compact: true) {
                    router.go(.meeting)
                }
                YapPillButton(title: "import", filled: false, compact: true) {
                    AudioImportPanel.chooseAndEnqueue(in: env)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    private var empty: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(YapTheme.coral.opacity(0.7))
                .symbolRenderingMode(.hierarchical)
            Text("no recordings yet")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("Start a recording in a meeting, or import an audio file.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                YapPillButton(title: "start recording") {
                    router.go(.meeting)
                }
                YapPillButton(title: "import audio", filled: false) {
                    AudioImportPanel.chooseAndEnqueue(in: env)
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionBlock(title: String, items: [TranscriptionJobRecord]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(Color.primary.opacity(0.88))
                Text("\(items.count) recording\(items.count == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.38))
            }
            .padding(.bottom, 10)

            ForEach(items, id: \.id) { job in
                YapRecordingRow(
                    job: job,
                    timeLabel: timeLabel(job),
                    durationLabel: durationLabel(job.durationSeconds),
                    stageLabel: stageLabel(job),
                    onOpen: { router.go(.job(job.id)) },
                    onRetry: { env.transcriptionRunner.retry(jobID: job.id) },
                    onPause: { env.transcriptionRunner.pause(jobID: job.id) },
                    onCancel: { env.transcriptionRunner.cancel(jobID: job.id) }
                )
            }
        }
    }

    private func sectionKey(for job: TranscriptionJobRecord, now: Date, calendar: Calendar) -> String {
        guard let date = parseISO(job.createdAt) else { return "earlier" }
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
            return "earlier this week"
        }
        if let monthAgo = calendar.date(byAdding: .day, value: -30, to: now), date >= monthAgo {
            return "last month"
        }
        return "earlier"
    }

    private func timeLabel(_ job: TranscriptionJobRecord) -> String {
        guard let date = parseISO(job.createdAt) else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date).lowercased()
    }

    private func durationLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%dh %dm %ds", total / 3600, (total % 3600) / 60, total % 60)
        }
        if total >= 60 {
            return String(format: "%dm %ds", total / 60, total % 60)
        }
        return "\(total)s"
    }

    private func parseISO(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let d = df.date(from: s) { return d }
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: s)
    }

    private func stageLabel(_ job: TranscriptionJobRecord) -> String {
        switch job.activeStage {
        case "preparingASR": return "Loading speech model"
        case "transcribing": return "Transcribing"
        case "preparingDiarizer": return "Loading speaker model"
        case "diarizing": return "Identifying speakers"
        case "aligning": return "Building transcript"
        default: return job.status.capitalized
        }
    }
}

// MARK: - Row

private struct YapRecordingRow: View {
    let job: TranscriptionJobRecord
    let timeLabel: String
    let durationLabel: String
    let stageLabel: String
    let onOpen: () -> Void
    let onRetry: () -> Void
    let onPause: () -> Void
    let onCancel: () -> Void

    @State private var hovering = false

    private var preview: String {
        (job.finalText ?? job.rawText ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tone: SemanticTone { SemanticTone.forStatus(job.status) }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 18) {
                // Time column — big time, small duration under it
                VStack(alignment: .leading, spacing: 3) {
                    Text(timeLabel)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.55))
                    Text(durationLabel)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.32))
                        .monospacedDigit()
                }
                .frame(width: 78, alignment: .leading)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    Text(job.sourceName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .lineLimit(1)
                    Text(preview.isEmpty ? stageLabel : preview)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.42))
                        .lineLimit(1)
                    if job.status == "running" || job.status == "queued" {
                        ProgressView(value: job.progress)
                            .controlSize(.small)
                            .tint(YapTheme.coral)
                            .padding(.top, 4)
                    }
                    if let err = job.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(SemanticTone.danger.color)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 12)

                trailingControls
                    .padding(.top, 2)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.055 : 0))
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(YapTheme.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, hovering ? 0 : 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 8) {
            if job.status == "completed" {
                Badge(title: "Ready", tone: .success)
                StatusDot(tone: .success, size: 10)
            } else if job.status == "failed" || job.status == "paused" {
                YapChipButton(systemImage: "arrow.clockwise", tint: YapTheme.coral, action: onRetry)
                YapChipButton(systemImage: "xmark", destructive: true, action: onCancel)
            } else if job.status == "running" {
                YapChipButton(systemImage: "pause.fill", tint: YapTheme.coral, action: onPause)
                YapChipButton(systemImage: "xmark", destructive: true, action: onCancel)
            } else if job.status == "queued" {
                ProgressView().controlSize(.small)
                YapChipButton(systemImage: "xmark", destructive: true, action: onCancel)
            } else {
                Badge(title: job.status.capitalized, tone: tone)
                StatusDot(tone: tone, size: 10)
            }
        }
        .opacity(hovering || job.status != "completed" ? 1 : 0.85)
    }
}

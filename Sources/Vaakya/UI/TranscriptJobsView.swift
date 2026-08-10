import SwiftUI
import VaakyaCore

struct TranscriptJobsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selectedJobID: String?

    var body: some View {
        VStack(spacing: 0) {
            if env.transcriptionRunner.jobs.isEmpty {
                emptyHero
            } else {
                filledLayout
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .background(VaakyaSurface.canvas)
        .onAppear {
            env.transcriptionRunner.refresh()
            selectNewestIfNeeded()
        }
        .onChange(of: env.transcriptionRunner.jobs.map(\.id)) {
            selectNewestIfNeeded()
        }
    }

    // MARK: - Empty (YapYap home energy: air + one CTA)

    private var emptyHero: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vaakya")
                            .font(.system(.title2, design: .default, weight: .semibold))
                            .tracking(-0.3)
                        Text("ready when you are")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, VaakyaSpace.panelInset)
                .padding(.top, VaakyaSpace.xl)

                Spacer(minLength: VaakyaSpace.hero)

                VStack(spacing: VaakyaSpace.lg) {
                    SoftPillButton(title: "Import audio", systemImage: "plus") {
                        AudioImportPanel.chooseAndEnqueue(in: env)
                    }
                    Text("Local Parakeet · speaker labels · insight lenses")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: VaakyaSpace.hero)

                Button("Choose a file…") {
                    AudioImportPanel.chooseAndEnqueue(in: env)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, VaakyaSpace.xxl)
            }

            if !env.config.diarizationModelConsentGiven {
                VStack {
                    Spacer()
                    InfoBanner(
                        text: "Speaker identification needs a one-time local model download.",
                        systemImage: "person.2.wave.2",
                        tone: .info,
                        actionTitle: "Allow Download",
                        action: { env.grantDiarizationConsent() }
                    )
                }
            }
        }
    }

    // MARK: - Filled master–detail

    private var filledLayout: some View {
        VStack(spacing: 0) {
            PanelHeader(
                title: "Transcripts",
                subtitle: "\(env.transcriptionRunner.jobs.count) recording\(env.transcriptionRunner.jobs.count == 1 ? "" : "s")"
            ) {
                SoftPillButton(title: "Import", systemImage: "plus", prominent: true) {
                    AudioImportPanel.chooseAndEnqueue(in: env)
                }
            }

            if !env.config.diarizationModelConsentGiven {
                InfoBanner(
                    text: "Speaker identification needs a one-time local model download.",
                    systemImage: "person.2.wave.2",
                    tone: .info,
                    actionTitle: "Allow Download",
                    action: { env.grantDiarizationConsent() }
                )
            }

            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(VaakyaSurface.hairline).frame(width: 1)
                detail
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECORDINGS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)
                .padding(.horizontal, VaakyaSpace.xl)
                .padding(.top, VaakyaSpace.lg)
                .padding(.bottom, VaakyaSpace.sm)

            ScrollView {
                LazyVStack(spacing: VaakyaSpace.sm) {
                    ForEach(env.transcriptionRunner.jobs, id: \.id) { job in
                        Button { selectedJobID = job.id } label: {
                            jobRow(job)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, VaakyaSpace.md)
                .padding(.bottom, VaakyaSpace.xl)
            }
        }
        .frame(width: 320)
        .background(VaakyaSurface.sidebar)
    }

    private var detail: some View {
        Group {
            if let selectedJobID {
                TranscriptDetailView(jobID: selectedJobID)
                    .id(selectedJobID)
            } else {
                ContentUnavailableView("Select a transcript", systemImage: "text.bubble")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VaakyaSurface.canvas)
    }

    /// List row: title + whisper stage · duration, status chip, status dot (YapYap library pattern).
    private func jobRow(_ job: TranscriptionJobRecord) -> some View {
        let selected = selectedJobID == job.id
        let tone = SemanticTone.forStatus(job.status)
        return HStack(alignment: .center, spacing: VaakyaSpace.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.sourceName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(stageLabel(job))
                    Text("·")
                    Text(duration(job.durationSeconds))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if job.status == "running" || job.status == "queued" {
                    ProgressView(value: job.progress)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
                if let error = job.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(SemanticTone.danger.color)
                        .lineLimit(2)
                }
                controls(for: job)
            }
            Spacer(minLength: 4)
            if job.status == "completed" {
                Badge(title: "Ready", tone: .success)
            } else if job.status != "running" && job.status != "queued" {
                Badge(title: job.status.capitalized, tone: tone)
            }
            StatusDot(tone: tone)
        }
        .padding(.horizontal, VaakyaSpace.md)
        .padding(.vertical, VaakyaSpace.rowY)
        .background(
            RoundedRectangle(cornerRadius: VaakyaRadius.row)
                .fill(selected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VaakyaRadius.row)
                .strokeBorder(selected ? Color.accentColor.opacity(0.22) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func controls(for job: TranscriptionJobRecord) -> some View {
        if job.status == "failed" || job.status == "paused" || job.status == "running" || job.status == "queued" {
            HStack(spacing: VaakyaSpace.md) {
                if job.status == "failed" || job.status == "paused" {
                    Button(job.status == "paused" ? "Resume" : "Retry") {
                        env.transcriptionRunner.retry(jobID: job.id)
                    }
                }
                if job.status == "running" {
                    Button("Pause") { env.transcriptionRunner.pause(jobID: job.id) }
                }
                if job.status == "queued" || job.status == "running" || job.status == "paused" {
                    Button("Cancel") { env.transcriptionRunner.cancel(jobID: job.id) }
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.top, 2)
        }
    }

    private func selectNewestIfNeeded() {
        guard selectedJobID == nil || !env.transcriptionRunner.jobs.contains(where: { $0.id == selectedJobID }) else { return }
        selectedJobID = env.transcriptionRunner.jobs.first?.id
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

    private func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60) }
        return String(format: "%dm %02ds", total / 60, total % 60)
    }
}

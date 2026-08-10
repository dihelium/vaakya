import SwiftUI
import VaakyaCore

/// Recording detail chrome: breadcrumb + status, body reuses TranscriptDetailView logic.
struct YapJobDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable private var router = ShellRouter.shared
    let jobID: String

    private var job: TranscriptionJobRecord? {
        env.transcriptionRunner.jobs.first(where: { $0.id == jobID })
            ?? (try? env.db.transcriptionJob(id: jobID))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                YapBreadcrumb(crumbs: [
                    ("vaakya", { router.popToRoot() }),
                    ("recordings", { router.goBack() }),
                    (job?.sourceName ?? "transcript", nil),
                ])
                Spacer()
                if let job {
                    if job.status == "completed" {
                        Badge(title: "Ready", tone: .success)
                    } else {
                        Badge(title: job.status.capitalized, tone: SemanticTone.forStatus(job.status))
                    }
                    StatusDot(tone: SemanticTone.forStatus(job.status))
                }
                Button {
                    router.goBack()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Back to recordings")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(YapTheme.canvas)

            Rectangle().fill(YapTheme.hairline).frame(height: 1)

            TranscriptDetailView(jobID: jobID)
                .background(YapTheme.canvas)
        }
        .background(YapTheme.canvas)
        .tint(YapTheme.coral)
        .onAppear { env.transcriptionRunner.refresh() }
    }
}

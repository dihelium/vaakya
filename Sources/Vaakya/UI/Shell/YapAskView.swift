import SwiftUI
import VaakyaCore

/// YAP-inspired Archive Ask: large type, pill chrome, live pending feedback.
struct YapAskView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable private var router = ShellRouter.shared

    @State private var conversations: [AskConversationRecord] = []
    @State private var activeID: String?
    @State private var messages: [AskMessageRecord] = []
    @State private var draft = ""
    @State private var scope: AskScope = .wholeArchive
    @State private var sending = false
    @State private var thinkingPhase = 0
    @State private var errorBanner: String?
    @State private var showPinSheet = false
    @State private var pinSelection: Set<String> = []
    @State private var jobTitles: [String: String] = [:]
    @State private var confirmB1 = false
    @State private var pendingB1Token: AskB1ConsentToken?
    @State private var statusWhisper = "ready when you are"
    @State private var appear = false

    private let thinkingLines = [
        "reading your archive…",
        "weighing notes and transcript…",
        "grounding citations…",
        "drafting an answer…",
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 280)
            Rectangle().fill(YapTheme.hairline).frame(width: 1)
            mainPane
        }
        .background(YapTheme.canvas)
        .onAppear {
            reloadAll()
            withAnimation(.easeOut(duration: 0.35)) { appear = true }
        }
        .sheet(isPresented: $showPinSheet) { pinSheet }
        .confirmationDialog(
            "Send text to \(env.config.runnerKind.label)?",
            isPresented: $confirmB1,
            titleVisibility: .visible
        ) {
            Button("Send selected recordings") {
                let token = env.askService.recordB1Consent(
                    scope: scope, runner: env.config.runnerKind)
                pendingB1Token = token
                Task { await performSend(b1Consent: token) }
            }
            Button("Cancel", role: .cancel) {
                pendingB1Token = nil
            }
        } message: {
            Text(env.askService.b1ConsentSummary(scope: scope, runner: env.config.runnerKind))
        }
        .onReceive(Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()) { _ in
            guard sending else { return }
            thinkingPhase = (thinkingPhase + 1) % thinkingLines.count
            statusWhisper = thinkingLines[thinkingPhase]
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(YapTheme.coral)
                        .frame(width: 44, height: 44)
                    HStack(spacing: 6) {
                        Circle().fill(Color.white.opacity(0.95)).frame(width: 5, height: 5)
                        Circle().fill(Color.white.opacity(0.95)).frame(width: 5, height: 5)
                    }
                    .offset(y: -1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("vaakya")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .tracking(-0.5)
                    Text(statusWhisper)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.42))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: statusWhisper)
                }
                Spacer(minLength: 4)
                Button {
                    if let id = activeID, sending {
                        env.askService.cancelInFlight(conversationID: id)
                        sending = false
                    }
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                        router.closeAskSheet()
                        if router.destination == .ask {
                            router.goBack()
                        }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .disabled(sending)
                .help("Close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 18)

            Button {
                guard !sending else { return }
                newConversation()
            } label: {
                Text("+ new conversation")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1.2)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
            .opacity(sending ? 0.45 : 1)

            if conversations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("no conversations yet")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.48))
                    Text("ask Vaakya something and it will show up here.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary.opacity(0.34))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.top, 28)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(conversations, id: \.id) { c in
                            conversationRow(c)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            Spacer()
        }
        .background(YapTheme.sidebar)
        .opacity(appear ? 1 : 0)
    }

    private func conversationRow(_ c: AskConversationRecord) -> some View {
        let selected = activeID == c.id
        return Button {
            guard !sending else { return }
            select(c)
        } label: {
            Text(c.title.isEmpty ? "New chat" : c.title)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(Color.primary.opacity(selected ? 0.92 : 0.55))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(selected ? 0.12 : 0))
                )
        }
        .buttonStyle(.plain)
        .disabled(sending && !selected)
        .contextMenu {
            Button("Delete", role: .destructive) {
                deleteConversation(c.id)
            }
            .disabled(sending && selected)
        }
    }

    // MARK: - Main

    private var mainPane: some View {
        VStack(spacing: 0) {
            if let errorBanner {
                Text(errorBanner)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
            }

            if messages.isEmpty && !sending {
                emptyStage
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(messages, id: \.id) { m in
                                messageBubble(m).id(m.id)
                            }
                            if sending, messages.last?.status != "pending" {
                                thinkingBubble.id("thinking")
                            }
                        }
                        .padding(.horizontal, 36)
                        .padding(.vertical, 28)
                    }
                    .onChange(of: messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: sending) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: messages.last?.status) { _, _ in
                        scrollToBottom(proxy)
                    }
                }
            }

            composerBar
        }
        .opacity(appear ? 1 : 0)
    }

    private var emptyStage: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)
            Text("Ask Vaakya anything about your archive")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .tracking(-0.4)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.primary.opacity(0.92))
            Text("what was decided, who said what, what is still open.")
                .font(.system(size: 17))
                .foregroundStyle(Color.primary.opacity(0.42))
                .multilineTextAlignment(.center)
            Text("Draft answers · grounded in selected recordings")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.32))
                .padding(.top, 8)
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageBubble(_ m: AskMessageRecord) -> some View {
        let isUser = m.role == "user"
        return VStack(alignment: .leading, spacing: 10) {
            Text(isUser ? "you" : "vaakya")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.primary.opacity(0.36))
                .textCase(.uppercase)

            if m.status == "pending" {
                thinkingBubbleContent
            } else {
                Text(LocalizedStringKey(m.content))
                    .font(.system(size: isUser ? 17 : 16.5))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .foregroundStyle(Color.primary.opacity(m.status == "error" || m.status == "interrupted" ? 0.72 : 0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if m.role == "assistant", m.status == "complete" {
                if let chips = citationChips(m), !chips.isEmpty {
                    FlowPills(items: chips) { chip in
                        router.go(.job(chip.jobID))
                    }
                }
                if let meta = sourceMeta(m) {
                    disclosureLine(meta)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isUser
                      ? Color.primary.opacity(0.07)
                      : YapTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(isUser ? 0.06 : 0.08), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var thinkingBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("vaakya")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.primary.opacity(0.36))
                .textCase(.uppercase)
            thinkingBubbleContent
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(YapTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(YapTheme.coral.opacity(0.25), lineWidth: 1)
        )
    }

    private var thinkingBubbleContent: some View {
        HStack(spacing: 14) {
            ThinkingDots()
            VStack(alignment: .leading, spacing: 4) {
                Text(thinkingLines[thinkingPhase])
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: thinkingPhase)
                Text(env.config.runnerKind.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.38))
            }
            Spacer()
        }
    }

    private func disclosureLine(_ meta: (omitted: Int, truncated: Int)) -> some View {
        Group {
            if meta.omitted > 0 || meta.truncated > 0 {
                Text(disclosureText(meta))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.38))
                    .padding(.top, 2)
            }
        }
    }

    private func disclosureText(_ meta: (omitted: Int, truncated: Int)) -> String {
        var parts: [String] = []
        if meta.truncated > 0 {
            parts.append("\(meta.truncated) recording\(meta.truncated == 1 ? "" : "s") truncated to fit context")
        }
        if meta.omitted > 0 {
            parts.append("\(meta.omitted) omitted")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Composer (YAP-style single field + plane)

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("reading")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.4))
                Text(scopeLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                    )
                Button {
                    guard !sending else { return }
                    openPinSheet()
                } label: {
                    Text("+ add")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(sending)
                Spacer()
                Text(env.config.runnerKind.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.32))
            }

            // One continuous capsule: field + send, like YAP.
            HStack(alignment: .center, spacing: 10) {
                TextField("Ask Vaakya anything…", text: $draft, axis: .vertical)
                    .font(.system(size: 16))
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .disabled(sending)
                    .onSubmit { attemptSend() }
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    attemptSend()
                } label: {
                    Group {
                        if sending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "paperplane")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(
                                    canSend
                                    ? YapTheme.coral
                                    : Color.primary.opacity(0.28)
                                )
                                .rotationEffect(.degrees(28))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help(canSend ? "Send" : "Type a question")
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            )
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }

    private var canSend: Bool {
        !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var scopeLabel: String {
        if scope.mode == .wholeArchive || scope.jobIDs.isEmpty {
            return "your whole archive"
        }
        if scope.jobIDs.count == 1, let id = scope.jobIDs.first {
            return jobTitles[id] ?? "1 recording"
        }
        return "\(scope.jobIDs.count) recordings"
    }

    // MARK: - Pin sheet

    private var pinSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pin recordings")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Required for Codex / Remote. Local may use whole archive.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            List(env.transcriptionRunner.jobs.filter { $0.status == "completed" }, id: \.id) { job in
                Toggle(isOn: Binding(
                    get: { pinSelection.contains(job.id) },
                    set: { on in
                        if on { pinSelection.insert(job.id) } else { pinSelection.remove(job.id) }
                    }
                )) {
                    Text(job.sourceName)
                        .font(.system(size: 15))
                }
            }
            HStack {
                Button("Whole archive") {
                    scope = .wholeArchive
                    pinSelection = []
                    persistScope()
                    showPinSheet = false
                }
                .font(.system(size: 15, weight: .medium))
                Spacer()
                Button("Done") {
                    if pinSelection.isEmpty {
                        scope = AskScope(mode: .wholeArchive, jobIDs: [], epoch: scope.epoch)
                    } else {
                        scope = AskScope(mode: .pinned, jobIDs: Array(pinSelection), epoch: scope.epoch)
                    }
                    persistScope()
                    showPinSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(YapTheme.coral)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460, height: 520)
    }

    // MARK: - Actions

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                } else if sending {
                    proxy.scrollTo("thinking", anchor: .bottom)
                }
            }
        }
    }

    private func reloadAll() {
        conversations = (try? env.askService.listConversations()) ?? []
        for j in env.transcriptionRunner.jobs {
            jobTitles[j.id] = j.sourceName
        }
        if activeID == nil, let first = conversations.first {
            select(first)
        } else if let id = activeID {
            messages = (try? env.askService.messages(conversationID: id)) ?? []
            if let c = conversations.first(where: { $0.id == id }) {
                scope = AskScope.parse(c.scopeJSON)
            }
        }
        if !sending {
            statusWhisper = "ready when you are"
        }
    }

    private func newConversation() {
        do {
            let c = try env.askService.createConversation(scope: scope)
            conversations.insert(c, at: 0)
            select(c)
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func select(_ c: AskConversationRecord) {
        activeID = c.id
        scope = AskScope.parse(c.scopeJSON)
        messages = (try? env.askService.messages(conversationID: c.id)) ?? []
        errorBanner = nil
        statusWhisper = "ready when you are"
    }

    private func deleteConversation(_ id: String) {
        if sending, activeID == id {
            env.askService.cancelInFlight(conversationID: id)
            sending = false
        }
        try? env.askService.deleteConversation(id: id)
        if activeID == id {
            activeID = nil
            messages = []
        }
        reloadAll()
    }

    private func openPinSheet() {
        pinSelection = Set(scope.jobIDs)
        env.transcriptionRunner.refresh()
        showPinSheet = true
    }

    private func persistScope() {
        guard let id = activeID else { return }
        try? env.askService.updateScope(conversationID: id, scope: scope)
        // Reload scope (epoch may have bumped) — history from old epoch stays in DB but is ignored.
        if let c = try? env.askService.listConversations().first(where: { $0.id == id }) {
            scope = AskScope.parse(c.scopeJSON)
        }
        reloadAll()
    }

    private func attemptSend() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        if activeID == nil {
            newConversation()
        }
        guard let id = activeID else { return }
        if env.askService.isInFlight(conversationID: id) {
            errorBanner = "Already answering this conversation."
            return
        }

        let runner = env.config.runnerKind
        if let blocked = env.askService.b1BlockedReason(scope: scope, runner: runner) {
            errorBanner = blocked
            return
        }
        if runner.isB1 {
            if env.askService.needsB1Consent(scope: scope, runner: runner) {
                confirmB1 = true
                return
            }
            // Consent already recorded this session for this fingerprint.
            let token = AskB1ConsentToken(
                fingerprint: env.askService.consentFingerprint(scope: scope, runner: runner))
            Task { await performSend(b1Consent: token) }
        } else {
            Task { await performSend(b1Consent: nil) }
        }
    }

    private func performSend(b1Consent: AskB1ConsentToken?) async {
        guard let id = activeID else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Optimistic UI: clear draft, show user bubble + thinking immediately.
        draft = ""
        sending = true
        thinkingPhase = 0
        statusWhisper = thinkingLines[0]
        errorBanner = nil

        let now = ISO8601DateFormatter().string(from: Date())
        let optimisticUser = AskMessageRecord(
            id: "local-user-\(UUID().uuidString)",
            conversationID: id,
            role: "user",
            content: text,
            status: "complete",
            scopeJSON: scope.jsonString(),
            createdAt: now,
            seq: (messages.last?.seq ?? 0) + 1)
        let optimisticPending = AskMessageRecord(
            id: "local-pending-\(UUID().uuidString)",
            conversationID: id,
            role: "assistant",
            content: "",
            status: "pending",
            scopeJSON: scope.jsonString(),
            createdAt: now,
            seq: optimisticUser.seq + 1)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            messages.append(optimisticUser)
            messages.append(optimisticPending)
        }

        defer {
            sending = false
            if errorBanner == nil {
                statusWhisper = "ready when you are"
            }
        }

        do {
            _ = try await env.askService.send(
                conversationID: id, text: text, b1Consent: b1Consent)
            let fresh = (try? env.askService.messages(conversationID: id)) ?? []
            withAnimation(.easeInOut(duration: 0.2)) {
                messages = fresh
            }
            conversations = (try? env.askService.listConversations()) ?? []
        } catch {
            errorBanner = error.localizedDescription
            statusWhisper = "something went wrong"
            if let idx = messages.lastIndex(where: { $0.status == "pending" }) {
                var failed = messages[idx]
                failed.status = "error"
                failed.content = error.localizedDescription
                failed.errorText = error.localizedDescription
                messages[idx] = failed
            }
            if let fresh = try? env.askService.messages(conversationID: id), !fresh.isEmpty {
                messages = fresh
            }
            conversations = (try? env.askService.listConversations()) ?? []
        }
    }

    private func citationChips(_ m: AskMessageRecord) -> [AskCitationChip]? {
        guard let json = m.sourcesJSON, let data = json.data(using: .utf8) else { return nil }
        struct Payload: Codable {
            var cited: [ArchiveCitation]
            var packed: [ArchiveSource]?
            var omittedJobIDs: [String]?
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p.cited.map {
            AskCitationChip(stableID: $0.stableID, jobID: $0.jobID, displayTitle: $0.displayTitle)
        }
    }

    private func sourceMeta(_ m: AskMessageRecord) -> (omitted: Int, truncated: Int)? {
        guard let json = m.sourcesJSON, let data = json.data(using: .utf8) else { return nil }
        struct Payload: Codable {
            var packed: [ArchiveSource]?
            var omittedJobIDs: [String]?
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let truncated = p.packed?.filter(\.truncated).count ?? 0
        let omitted = p.omittedJobIDs?.count ?? 0
        if truncated == 0 && omitted == 0 { return nil }
        return (omitted, truncated)
    }
}

struct AskCitationChip: Identifiable, Equatable {
    var stableID: String
    var jobID: String
    var displayTitle: String
    var id: String { stableID }
}

// MARK: - Thinking dots

private struct ThinkingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(YapTheme.coral.opacity(phase == i ? 0.95 : 0.35))
                    .frame(width: 8, height: 8)
                    .scaleEffect(phase == i ? 1.15 : 0.9)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - Flow of large pills

private struct FlowPills: View {
    struct Item: Identifiable {
        var id: String
        var title: String
        var jobID: String
    }

    let items: [Item]
    let onTap: (Item) -> Void

    init(items: [AskCitationChip], onTap: @escaping (AskCitationChip) -> Void) {
        self.items = items.map {
            Item(id: $0.stableID, title: "\($0.stableID) · \($0.displayTitle)", jobID: $0.jobID)
        }
        self.onTap = { item in
            if let chip = items.first(where: { $0.stableID == item.id }) {
                onTap(chip)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { item in
                        Button {
                            onTap(item)
                        } label: {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(YapTheme.coral.opacity(0.14))
                                )
                                .foregroundStyle(YapTheme.coral)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var rows: [[Item]] {
        var result: [[Item]] = [[]]
        var width = 0
        for item in items {
            let w = item.title.count
            if width + w > 48, !result[result.count - 1].isEmpty {
                result.append([item])
                width = w
            } else {
                result[result.count - 1].append(item)
                width += w + 2
            }
        }
        return result.filter { !$0.isEmpty }
    }
}

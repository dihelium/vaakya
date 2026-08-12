import SwiftUI
import VaakyaCore

/// Create or edit a user lens. Saved as Markdown under Application Support.
struct CustomLensEditorSheet: View {
    enum Mode: Equatable, Identifiable {
        case create
        case edit(LensSpec)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let spec): return "edit-\(spec.id)"
            }
        }
    }

    let mode: Mode
    let onSave: (String?, String, String) throws -> LensSpec
    let onCancel: () -> Void
    let onSaved: (LensSpec) -> Void

    @State private var title: String = ""
    @State private var bodyText: String = CustomLensStore.defaultInstructions
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .create ? "Create lens" : "Edit lens")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("This prompt runs on a completed transcript. Audio never leaves this Mac. The same egress rules as bundled lenses still apply.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Title — e.g. Standup minutes", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15))

            if case .edit(let spec) = mode {
                Text("id: \(spec.id)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Instructions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $bodyText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 240)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                )

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(mode == .create ? "Create lens" : "Save lens") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(YapTheme.coral)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 480)
        .onAppear { seed() }
    }

    private func seed() {
        if case .edit(let spec) = mode {
            title = spec.title
            bodyText = spec.body
        }
    }

    private func save() {
        error = nil
        do {
            let existingID: String?
            if case .edit(let spec) = mode {
                existingID = spec.id
            } else {
                existingID = nil
            }
            let spec = try onSave(existingID, title, bodyText)
            onSaved(spec)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

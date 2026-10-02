import SwiftUI

/// The models on this Mac and the space each takes, with Delete, so a
/// model tried once doesn't keep a gigabyte or two. Sizes are measured off
/// the main thread when the section appears and after each delete.
@MainActor
final class ModelStorage: ObservableObject {
    struct Entry: Identifiable {
        let model: TranscriptionModel
        let bytes: Int64
        var id: String { model.id }
    }

    @Published private(set) var entries: [Entry] = []

    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }

    func refresh() {
        Task.detached(priority: .utility) {
            let entries = ModelRegistry.shared.compactMap { model in
                WhisperKitTranscriber.diskBytes(model).map { Entry(model: model, bytes: $0) }
            }
            await MainActor.run { self.entries = entries.sorted { $0.bytes > $1.bytes } }
        }
    }

    func delete(_ model: TranscriptionModel) {
        do {
            try WhisperKitTranscriber.deleteDownload(model)
        } catch {
            Log.warning("couldn't delete \(model.id): \(error.localizedDescription)")
        }
        refresh()
    }

    /// Two significant figures are plenty for disk use: "650 MB", "1.6 GB".
    static func format(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        if mb >= 100 { return String(format: "%.0f MB", (mb / 10).rounded() * 10) }
        return String(format: "%.0f MB", mb)
    }
}

/// Rows in the Transcription section: the total, then each downloaded
/// model. The model in use, or one loading, can't be deleted.
struct DownloadedModels: View {
    /// The model chosen in Settings.
    let selected: TranscriptionModel?
    @StateObject private var storage = ModelStorage()
    @ObservedObject private var loading = ModelLoadStatus.shared
    @State private var confirming: ModelStorage.Entry?

    var body: some View {
        if !storage.entries.isEmpty {
            HStack {
                Text("On this Mac").font(.headline)
                Spacer()
                Text("\(ModelStorage.format(storage.totalBytes)) in all")
                    .foregroundStyle(.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(storage.entries) { entry in
                HStack {
                    Text(entry.model.displayName.replacingOccurrences(of: "Whisper ", with: ""))
                    Spacer()
                    Text(ModelStorage.format(entry.bytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if isInUse(entry.model) {
                        Text("In use")
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 64, alignment: .trailing)
                    } else {
                        Button("Delete…") { confirming = entry }
                            .buttonStyle(.pill)
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                }
                .font(.callout)
            }
        }
        .onAppear { storage.refresh() }
        .onChange(of: loading.current) { _, state in
            // A download just finished: it is on the Mac now.
            if state == nil { storage.refresh() }
        }
        .confirmationDialog(
            confirming.map { "Delete \($0.model.displayName)?" } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { entry in
            Button("Delete", role: .destructive) {
                storage.delete(entry.model)
            }
        } message: { entry in
            Text("Frees \(ModelStorage.format(entry.bytes)). It downloads again if you choose it later.")
        }
    }

    private func isInUse(_ model: TranscriptionModel) -> Bool {
        model.id == selected?.id || model.id == loading.current?.modelID
    }
}

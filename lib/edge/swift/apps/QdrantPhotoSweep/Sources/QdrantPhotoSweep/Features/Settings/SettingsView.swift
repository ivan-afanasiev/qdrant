import SwiftUI

struct SettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = SettingsState()

    var body: some View {
        Form {
            thresholdSection
            databaseSection
            aboutSection
        }
        .navigationTitle("Settings")
        .task {
            await loadInfo()
        }
    }

    private var thresholdSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Similarity Threshold")
                    Spacer()
                    Text(String(format: "%.0f%%", state.similarityThreshold * 100))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $state.similarityThreshold, in: 0.7...0.99, step: 0.01)
                Text("Higher values find only very similar photos. Lower values find more potential duplicates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Detection")
        }
    }

    @ViewBuilder
    private var databaseSection: some View {
        Section {
            switch state.status {
            case .idle(let count):
                HStack {
                    Text("Indexed Photos")
                    Spacer()
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button(role: .destructive) {
                    clearDatabase()
                } label: {
                    Label("Clear Database", systemImage: "trash")
                }
                .disabled(count == 0)

            case .clearing:
                HStack {
                    ProgressView()
                    Text("Clearing...")
                        .foregroundStyle(.secondary)
                }

            case .cleared:
                Label("Database cleared", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)

            case .failed(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        } header: {
            Text("Database")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Engine")
                Spacer()
                Text("Qdrant Edge")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Embeddings")
                Spacer()
                Text("Apple Vision")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Dimensions")
                Spacer()
                Text("768")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } header: {
            Text("About")
        }
    }

    private func loadInfo() async {
        guard let deps = dependencies else { return }
        do {
            let count = try await deps.vectorStore.count()
            state.reduce(.didLoadInfo(pointCount: count))
        } catch {
            state.reduce(.didFail(error))
        }
    }

    private func clearDatabase() {
        guard let deps = dependencies else { return }
        state.reduce(.didTapClearDatabase)
        Task {
            do {
                var offset: String? = nil
                while true {
                    let page = try await deps.vectorStore.scroll(offset: offset, limit: 100)
                    guard !page.records.isEmpty else { break }
                    let ids = page.records.map(\.id)
                    try await deps.vectorStore.delete(ids: ids)
                    offset = page.nextOffset
                    guard offset != nil else { break }
                }
                state.reduce(.didFinishClearing)
            } catch let error as AppError {
                state.reduce(.didFail(error))
            } catch {
                state.reduce(.didFail(.unknown(error.localizedDescription)))
            }
        }
    }
}

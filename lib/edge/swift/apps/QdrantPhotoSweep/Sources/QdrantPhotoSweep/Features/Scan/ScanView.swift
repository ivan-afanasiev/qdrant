import SwiftUI

struct ScanView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = ScanState()
    @State private var scanTask: Task<Void, Never>?

    let dateRange: DateRange
    let onComplete: ([DuplicateGroup]) -> Void

    var body: some View {
        VStack(spacing: 24) {
            switch state.status {
            case .idle:
                idleView

            case .scanning(let processed, let total):
                scanningView(processed: processed, total: total)

            case .completed(let indexed):
                completedView(indexed: indexed)

            case .failed(let error):
                failedView(error: error)

            case .cancelled:
                cancelledView
            }
        }
        .padding()
        .navigationTitle("Scanning")
        .navigationBarBackButtonHidden(isScanActive)
        .task {
            startScan()
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private var isScanActive: Bool {
        switch state.status {
        case .scanning: true
        default: false
        }
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Preparing to scan...")
                .foregroundStyle(.secondary)
        }
    }

    private func scanningView(processed: Int, total: Int) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(lineWidth: 8)
                    .foregroundStyle(.fill.quaternary)
                Circle()
                    .trim(from: 0, to: state.progress)
                    .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .foregroundStyle(.tint)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: state.progress)
                VStack {
                    Text("\(Int(state.progress * 100))%")
                        .font(.title.bold().monospacedDigit())
                    Text("\(processed) / \(total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)

            Text("Embedding photos...")
                .font(.headline)
            Text("Processing images and building vector database")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(role: .destructive) {
                scanTask?.cancel()
                state.reduce(.didTapCancel)
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)
        }
    }

    private func completedView(indexed: Int) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Scan Complete")
                .font(.title2.bold())
            Text("\(indexed) photos indexed")
                .foregroundStyle(.secondary)

            Button {
                findDuplicates()
            } label: {
                Label("Find Duplicates", systemImage: "sparkle.magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func failedView(error: AppError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Scan Failed")
                .font(.title2.bold())
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                startScan()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var cancelledView: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Scan Cancelled")
                .font(.title2.bold())

            Button("Retry") {
                startScan()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func startScan() {
        guard let deps = dependencies else { return }
        scanTask?.cancel()
        scanTask = Task {
            let pipeline = ScanPipeline(
                photoLibrary: deps.photoLibrary,
                embeddingService: deps.embeddingService,
                vectorStore: deps.vectorStore
            )
            await pipeline.run(dateRange: dateRange, state: state)
        }
    }

    @State private var detectionState = DuplicateDetectionState()

    private func findDuplicates() {
        guard let deps = dependencies else { return }
        Task {
            await detectionState.findDuplicates(
                vectorStore: deps.vectorStore,
                threshold: 0.92
            )
            switch detectionState.status {
            case .complete(let groups):
                onComplete(groups)
            default:
                break
            }
        }
    }
}

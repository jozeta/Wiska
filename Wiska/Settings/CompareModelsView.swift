import Cleanup
import Core
import SwiftUI

/// Settings → Cleanup → Compare models: the benchmark through each available model.
struct CompareModelsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var results: [String: [Int: BenchmarkResult]] = [:]
    @State private var running = false
    @State private var runTask: Task<Void, Never>?

    var body: some View {
        let engines = model.benchmarkEngines()
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Compare models").font(.headline)
                Spacer()
                ForEach(engines, id: \.name) { engine in
                    if let summary = summary(engine.name) { Text(summary).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if engines.isEmpty {
                Text("No language model is available. Turn on Apple Intelligence or download Gemma.")
                    .foregroundStyle(.secondary)
            }
            List(ModelBenchmark.cases) { benchmarkCase in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(benchmarkCase.title) — “\(benchmarkCase.input)”").font(.callout.bold()).lineLimit(2)
                    ForEach(engines, id: \.name) { engine in
                        if let result = results[engine.name]?[benchmarkCase.id] {
                            HStack(alignment: .top) {
                                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.passed ? .green : .red)
                                Text(engine.name).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                                Text(result.output).textSelection(.enabled)
                                Spacer()
                                Text(result.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text("Nothing is saved. Grammar cases run with Fix grammar on.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { runTask?.cancel(); dismiss() }
                Button(running ? "Running…" : "Run") { run(engines) }
                    .disabled(running || engines.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 760, height: 620)
        .onDisappear { runTask?.cancel() }   // closed mid-run: stop using the GPU
    }

    private func summary(_ name: String) -> String? {
        guard let done = results[name], !done.isEmpty else { return nil }
        let passed = done.values.filter(\.passed).count
        let average = done.values.map(\.duration).reduce(.zero, +) / done.count
        return "\(name): \(passed)/\(done.count) · \(average.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))) avg"
    }

    private func run(_ engines: [(name: String, rewriter: any TextRewriter, editor: any Core.TextEditor)]) {
        running = true
        results = [:]
        runTask = Task {
            for engine in engines {
                for benchmarkCase in ModelBenchmark.cases {
                    guard !Task.isCancelled else { break }
                    let result = await ModelBenchmark.run(benchmarkCase, rewriter: engine.rewriter, editor: engine.editor)
                    results[engine.name, default: [:]][benchmarkCase.id] = result
                }
            }
            running = false
        }
    }
}

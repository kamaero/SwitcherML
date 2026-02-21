import Foundation
import CreateML
import CoreML

/// Trains an MLBoostedTreeClassifier on labeled ConversionSamples whenever
/// enough data has accumulated, then compiles and delivers the model.
/// Training runs on a background thread; the callback fires on the main thread.
final class OnDeviceTrainer {

    static let minimumSamples = 200
    private let retrainInterval = 100

    private var lastTrainedCount = 0

    /// Called on the main thread when a new model is ready.
    var onModelReady: ((MLModel) -> Void)?

    private let modelURL: URL
    private let compiledModelURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("SwitcherLM", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        modelURL = appSupport.appendingPathComponent("SwitcherLM.mlmodel")
        compiledModelURL = appSupport.appendingPathComponent("SwitcherLM.mlmodelc")
    }

    /// Train if we have enough samples and enough new samples since last run.
    func trainIfReady(samples: [ConversionSample]) {
        let count = samples.count
        guard count >= Self.minimumSamples else { return }
        guard count >= lastTrainedCount + retrainInterval || lastTrainedCount == 0 else { return }
        lastTrainedCount = count

        let snapshot = samples
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.performTraining(samples: snapshot)
        }
    }

    /// Load a previously compiled model from disk (called at startup).
    func loadExistingModel() -> MLModel? {
        guard FileManager.default.fileExists(atPath: compiledModelURL.path) else { return nil }
        return try? MLModel(contentsOf: compiledModelURL)
    }

    // MARK: - Private

    private func performTraining(samples: [ConversionSample]) {
        do {
            let csvURL = try buildCSV(samples: samples)
            let table = try MLDataTable(contentsOf: csvURL)

            let classifier = try MLBoostedTreeClassifier(
                trainingData: table,
                targetColumn: "label"
            )
            try classifier.write(to: modelURL)

            let compiledURL = try MLModel.compileModel(at: modelURL)
            let model = try MLModel(contentsOf: compiledURL)

            // Copy compiled bundle to persistent location
            try? FileManager.default.removeItem(at: compiledModelURL)
            try FileManager.default.copyItem(at: compiledURL, to: compiledModelURL)

            DispatchQueue.main.async { [weak self] in
                print("OnDeviceTrainer: Model ready — trained on \(samples.count) samples")
                self?.onModelReady?(model)
            }
        } catch {
            print("OnDeviceTrainer: Training failed: \(error)")
        }
    }

    private func buildCSV(samples: [ConversionSample]) throws -> URL {
        var lines = ["ruConf,enConf,appBias,spellEn,spellRu,wasLatin,label"]
        for s in samples {
            let line = [
                s.sessionRuConf,
                s.sessionEnConf,
                s.appBias,
                s.spellValidEn ? 1.0 : 0.0,
                s.spellValidRu ? 1.0 : 0.0,
                s.wasLatin ? 1.0 : 0.0,
            ].map { String(format: "%.6f", $0) }.joined(separator: ",")
            lines.append("\(line),\(s.label ?? "skip")")
        }
        let csvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("switcher_ml_training.csv")
        try lines.joined(separator: "\n").write(to: csvURL, atomically: true, encoding: .utf8)
        return csvURL
    }
}

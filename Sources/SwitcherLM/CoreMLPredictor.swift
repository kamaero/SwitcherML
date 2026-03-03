import Foundation
import CoreML

/// Wraps a compiled CoreML classifier (trained by OnDeviceTrainer) to predict
/// whether a word should be converted or skipped.
final class CoreMLPredictor {

    private let model: MLModel

    init(model: MLModel) {
        self.model = model
    }

    /// Returns `("convert"/"skip", confidence)` or `nil` on error.
    /// Input feature names must match the columns used during training.
    func predict(
        sessionRuConf: Double,
        sessionEnConf: Double,
        appBias: Double,
        spellEn: Bool,
        spellRu: Bool,
        wasLatin: Bool
    ) -> (label: String, confidence: Double)? {
        do {
            let features: [String: MLFeatureValue] = [
                "ruConf":    MLFeatureValue(double: sessionRuConf),
                "enConf":    MLFeatureValue(double: sessionEnConf),
                "appBias":   MLFeatureValue(double: appBias),
                "spellEn":   MLFeatureValue(double: spellEn ? 1.0 : 0.0),
                "spellRu":   MLFeatureValue(double: spellRu ? 1.0 : 0.0),
                "wasLatin":  MLFeatureValue(double: wasLatin ? 1.0 : 0.0),
            ]
            let provider = try MLDictionaryFeatureProvider(dictionary: features)
            let result = try model.prediction(from: provider)

            // CreateML classifiers output "classLabel" and "classProbability"
            guard let label = result.featureValue(for: "classLabel")?.stringValue else {
                return nil
            }
            let probs = result.featureValue(for: "classProbability")?.dictionaryValue
            let confidence = (probs?[label as NSObject] as? Double) ?? 0.5
            return (label, confidence)
        } catch {
            print("CoreMLPredictor: Prediction failed: \(error)")
            return nil
        }
    }
}

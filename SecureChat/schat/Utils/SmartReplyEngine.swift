import Foundation
import NaturalLanguage

class SmartReplyEngine {
    private let model: NLModel?

    init() {
        if let modelURL = Bundle.main.url(forResource: "SmartReplies", withExtension: "mlmodelc") {
            model = try? NLModel(contentsOf: modelURL)
        } else {
            model = nil
        }
    }

    func suggestions(for text: String) -> [String] {
        guard let label = model?.predictedLabel(for: text) else { return [] }
        return [label]
    }
}

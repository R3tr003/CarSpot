import Accelerate
import CoreML
import Foundation
import ImageIO
import os

private let log = Logger(subsystem: "com.carspot.andrea.app", category: "recognition")

/// Riconoscimento sul telefono, senza rete: l'encoder immagine SigLIP2 (Core ML, `CarEncoder`)
/// trasforma la foto in un vettore che si confronta con i vettori di testo dei modelli del
/// catalogo (`car-embeddings.f16` + `car-labels.json`). File generati da
/// `tools/recognition-trial` (`convert_coreml.py`, `catalog_embeddings.py export-app`).
actor OnDeviceRecognitionService: RecognitionService {

    /// L'encoder è gitignorato (93 MB): senza, `AppConfig` ripiega sul mock.
    static var isAvailable: Bool { Bundle.main.url(forResource: "CarEncoder", withExtension: "mlmodelc") != nil }

    private var loaded: (model: MLModel, ranker: CarRanker)?

    func recognize(imageData: Data) async throws -> [VehicleCandidate] {
        let (model, ranker) = try load()
        let input = try MLDictionaryFeatureProvider(dictionary: ["pixel_values": try Self.pixels(from: imageData)])
        let output = try Self.predict(model, input)
        guard let embedding = output.featureValue(for: "image_embeds")?.multiArrayValue else {
            throw RecognitionError.noMatch
        }
        let result = ranker.rank(embedding: (0..<embedding.count).map { embedding[$0].floatValue })
        guard !result.isEmpty else { throw RecognitionError.noMatch }
        return result
    }

    /// Versione sincrona: `MLModel` non è Sendable (quella async lo farebbe uscire dall'actor),
    /// e l'actor gira già fuori dal main thread.
    private static func predict(_ model: MLModel, _ input: MLFeatureProvider) throws -> MLFeatureProvider {
        try model.prediction(from: input)
    }

    /// Caricamento pigro alla prima foto (modello ~1 s, vettori ~12 MB).
    private func load() throws -> (MLModel, CarRanker) {
        if let loaded { return loaded }
        guard let modelURL = Bundle.main.url(forResource: "CarEncoder", withExtension: "mlmodelc"),
              let vectors = Bundle.main.url(forResource: "car-embeddings", withExtension: "f16"),
              let labels = Bundle.main.url(forResource: "car-labels", withExtension: "json") else {
            log.error("Risorse del riconoscimento mancanti nel bundle")
            throw RecognitionError.noMatch
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: modelURL, configuration: config)
        let ranker = try CarRanker(labels: Data(contentsOf: labels), vectors: Data(contentsOf: vectors))
        loaded = (model, ranker)
        return (model, ranker)
    }

    static let side = 256

    /// Come il processor di SigLIP2: RGB 256×256 senza crop, poi (x/255 − 0,5)/0,5, layout (1, 3, H, W).
    /// La miniatura di ImageIO applica già l'orientamento EXIF.
    static func pixels(from data: Data) throws -> MLMultiArray {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 2
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw RecognitionError.noMatch
        }
        // Miniatura 512 + .high: la combinazione più vicina al bilineare di PIL (coseno ≥ 0,986).
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let raw = context.data else { throw RecognitionError.noMatch }

        let plane = side * side
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
        let rgba = raw.bindMemory(to: UInt8.self, capacity: plane * 4)
        let out = array.dataPointer.bindMemory(to: Float.self, capacity: plane * 3)
        for i in 0..<plane {
            out[i] = Float(rgba[i * 4]) / 127.5 - 1
            out[plane + i] = Float(rgba[i * 4 + 1]) / 127.5 - 1
            out[2 * plane + i] = Float(rgba[i * 4 + 2]) / 127.5 - 1
        }
        return array
    }
}

/// Classifica un vettore immagine contro i modelli del catalogo. Separato dall'encoder per i test.
struct CarRanker: Sendable {

    struct Labels: Decodable, Sendable {
        let dim: Int
        let logitScale: Float
        /// Peso di log(1 + popolarità): favorisce le auto comuni senza escludere le rare.
        let popularityWeight: Float
        let models: [Entry]
    }

    struct Entry: Decodable, Sendable {
        let id: String
        let make: String
        let model: String
        /// Indice del modello "capofamiglia": il catalogo divide le generazioni ("A5", "A5 8T").
        let family: Int
        let popularity: Int
        let yearStart: Int?
        let yearEnd: Int?
    }

    let labels: Labels
    /// Matrice row-major `count × dim`, righe L2-normalizzate.
    private let matrix: [Float]
    private let prior: [Float]

    init(labels: Data, vectors: Data) throws {
        let decoded = try JSONDecoder().decode(Labels.self, from: labels)
        let count = decoded.models.count
        guard vectors.count == count * decoded.dim * MemoryLayout<Float16>.size else {
            throw RecognitionError.noMatch
        }
        self.labels = decoded
        self.matrix = vectors.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)).map(Float.init) }
        self.prior = decoded.models.map { decoded.popularityWeight * log1p(Float($0.popularity)) }
    }

    /// Le prime `limit` famiglie per probabilità (softmax), rappresentate dal loro modello più probabile.
    func rank(embedding: [Float], limit: Int = 3) -> [VehicleCandidate] {
        let count = labels.models.count
        guard embedding.count == labels.dim, count > 0 else { return [] }
        let norm = sqrt(vDSP.sumOfSquares(embedding))
        guard norm > 0 else { return [] }
        let e = vDSP.divide(embedding, norm)

        var cos = [Float](repeating: 0, count: count)
        vDSP_mmul(matrix, 1, e, 1, &cos, 1, vDSP_Length(count), 1, vDSP_Length(labels.dim))
        let logits = vDSP.add(vDSP.multiply(labels.logitScale, cos), prior)
        let top = vDSP.maximum(logits)
        let exp = logits.map { Foundation.exp($0 - top) }
        let total = vDSP.sum(exp)

        var families: [Int: (best: Int, p: Float)] = [:]
        for i in exp.indices.sorted(by: { exp[$0] > exp[$1] }).prefix(50) {
            let family = labels.models[i].family
            let p = exp[i] / total
            families[family] = families[family].map { ($0.best, $0.p + p) } ?? (i, p)
        }
        return families.values.sorted { $0.p > $1.p }.prefix(limit).map { best, p in
            let entry = labels.models[best]
            return VehicleCandidate(make: entry.make, model: entry.model,
                                    yearEstimate: Self.year(entry), confidence: Double(min(p, 1)))
        }
    }

    /// Metà del periodo di produzione, se noto per intero; altrimenti la sceglie il flusso di salvataggio.
    static func year(_ entry: Entry) -> Int? {
        guard let start = entry.yearStart, let end = entry.yearEnd else { return nil }
        return (start + end) / 2
    }
}

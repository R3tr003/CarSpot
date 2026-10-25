import Testing
import UIKit
@testable import CarSpot

/// Privacy: l'anonimizzazione è fail-closed. Il rilevatore Vision è sostituito da uno finto.
struct ImageAnonymizerTests {

    private struct DetectorFailure: Error {}

    /// JPEG a scacchiera: la sfocatura ne cambia sicuramente i pixel.
    private static func sampleJPEG() throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format)
        let image = renderer.image { ctx in
            for row in 0..<20 {
                for col in 0..<20 where (row + col).isMultiple(of: 2) {
                    UIColor.white.setFill()
                    ctx.fill(CGRect(x: col * 10, y: row * 10, width: 10, height: 10))
                }
            }
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    // MARK: Fail-closed

    @Test func visionErrorThrowsAndReturnsNothing() throws {
        let input = try Self.sampleJPEG()
        #expect(throws: AnonymizationError.analysisFailed) {
            _ = try ImageAnonymizer.anonymize(jpegData: input) { _ in throw DetectorFailure() }
        }
    }

    @Test func undecodableDataThrows() {
        #expect(throws: AnonymizationError.undecodable) {
            _ = try ImageAnonymizer.anonymize(jpegData: Data("non è un'immagine".utf8)) { _ in [] }
        }
    }

    @Test func emptyDataThrows() {
        #expect(throws: AnonymizationError.undecodable) {
            _ = try ImageAnonymizer.anonymize(jpegData: Data()) { _ in [] }
        }
    }

    // MARK: Esiti ok

    @Test func noSensitiveRegionsPassesImageThroughUnchanged() throws {
        let input = try Self.sampleJPEG()
        let output = try ImageAnonymizer.anonymize(jpegData: input) { _ in [] }
        #expect(output == input)
    }

    @Test func sensitiveRegionIsBlurredAndImageStaysDecodable() throws {
        let input = try Self.sampleJPEG()
        let region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let output = try ImageAnonymizer.anonymize(jpegData: input) { _ in [region] }
        #expect(output != input)
        let decoded = try #require(UIImage(data: output))
        #expect(decoded.size == CGSize(width: 200, height: 200))
    }

    // MARK: looksLikePlate

    @Test(arguments: ["AB123CD", "AB 123 CD", "MI 123456", "MI123456", "1234ABC", "B1234"])
    func plateLikeTextIsDetected(_ text: String) {
        #expect(ImageAnonymizer.looksLikePlate(text))
    }

    @Test(arguments: ["FERRARI", "CARSPOT", "ABCDEFGH", "AB12", "AB123CD45E", "ab123cd", "AB-123-CD", "", "12 34"])
    func nonPlateTextIsIgnored(_ text: String) {
        #expect(!ImageAnonymizer.looksLikePlate(text))
    }
}

import Foundation

/// Calls the Supabase `recognize` Edge Function, which fronts the recognition
/// provider (e.g. CarNet.AI) so the API key never ships in the app. Sends the
/// already-anonymized JPEG as base64 JSON.
struct RemoteRecognitionService: RecognitionService {

    private struct Request: Encodable { let imageBase64: String }
    private struct Response: Decodable { let candidates: [VehicleCandidate] }

    func recognize(imageData: Data) async throws -> [VehicleCandidate] {
        var request = URLRequest(url: AppConfig.recognitionEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConfig.supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.supabaseKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(Request(imageBase64: imageData.base64EncodedString()))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw RecognitionError.network("status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard !decoded.candidates.isEmpty else { throw RecognitionError.noMatch }
            return decoded.candidates
        } catch let error as RecognitionError {
            throw error
        } catch {
            throw RecognitionError.network(error.localizedDescription)
        }
    }
}

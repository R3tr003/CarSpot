import Foundation

/// Calls the Supabase `recognize` Edge Function, which fronts the recognition
/// provider (e.g. CarNet.AI) so the API key never ships in the app. Sends the
/// already-anonymized JPEG as base64 JSON. L'identità è il JWT Clerk (`Authorization`),
/// chiesto a ogni richiesta e mai salvato; la publishable key (`apikey`) non autentica.
struct RemoteRecognitionService: RecognitionService {

    private struct Request: Encodable { let imageBase64: String }
    private struct Response: Decodable { let candidates: [VehicleCandidate] }

    /// Passa dal main actor: l'esistenziale `any AuthService` non è `Sendable`, esce solo la stringa.
    @MainActor
    private static func sessionToken() async throws -> String? {
        try await AppServices.auth.sessionToken()
    }

    func recognize(imageData: Data) async throws -> [VehicleCandidate] {
        // Token di sessione Clerk (~1 min): senza sessione non si chiama nemmeno la function.
        guard let token = try await Self.sessionToken() else {
            throw RecognitionError.unauthorized
        }

        var request = URLRequest(url: AppConfig.recognitionEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.supabaseKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(Request(imageBase64: imageData.base64EncodedString()))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RecognitionError.network("status -1")
            }
            switch http.statusCode {
            case 200..<300: break
            case 401: throw RecognitionError.unauthorized
            case 429: throw RecognitionError.rateLimited
            default: throw RecognitionError.network("status \(http.statusCode)")
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

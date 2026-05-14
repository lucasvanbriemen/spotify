import Foundation

class SeverApi {
    private static let baseUrl: String = Secrets.base_url
    private static let apiKey: String = Secrets.api_key
    
    public static func get<T: Decodable>(endpoint: String) async -> T? {
        return await makeRequest(endpoint: endpoint)
    }

    public static func post<T: Decodable>(endpoint: String, body: [String: Any]) async -> T? {
        let data = try? JSONSerialization.data(withJSONObject: body)
        return await makeRequest(method: "POST", endpoint: endpoint, data: data)
    }

    private static func makeRequest<T: Decodable>(method: String = "GET", endpoint: String, data: Data? = nil) async -> T? {
        do {
            var request = URLRequest(url: URL(string: "\(baseUrl)\(endpoint)")!)
            request.httpMethod = method

            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            if let data {
                request.httpBody = data
            }

            let (responseData, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(T.self, from: responseData)
        } catch {
            print("server API failed \(error)")
            return nil
        }
    }
}

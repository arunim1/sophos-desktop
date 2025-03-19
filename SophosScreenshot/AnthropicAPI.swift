import Foundation
import Security
import SwiftAnthropic

class AnthropicAPI {
    static let shared = AnthropicAPI()
    
    private let model = Model.claude3Sonnet // Using claude-3-sonnet model
    private let maxTokens = 1024
    private var service: AnthropicServiceProtocol?
    
    private func getAPIKey() -> String? {
        print("Attempting to retrieve API key from keychain")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.sophos.screenshot",
            kSecAttrAccount as String: "anthropic_api_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        print("Keychain query status: \(status)")
        
        if status == errSecSuccess, let data = result as? Data {
            let apiKey = String(data: data, encoding: .utf8)
            if let key = apiKey {
                let masked = key.count > 8 ? 
                    String(key.prefix(4)) + "..." + String(key.suffix(4)) : 
                    "[Invalid key]"
                print("API Key found in keychain (masked): \(masked)")
                return key
            } else {
                print("API Key found but could not decode as UTF-8 string")
                return nil
            }
        } else if status == errSecItemNotFound {
            print("API Key not found in keychain")
            
            // For testing only - REMOVE IN PRODUCTION
            // Check if there's a key in UserDefaults as a fallback
            if let fallbackKey = UserDefaults.standard.string(forKey: "anthropic_api_key") {
                print("Found fallback API key in UserDefaults")
                return fallbackKey
            }
        } else {
            print("Keychain error: \(status)")
        }
        
        return nil
    }
    
    // Text summarization function using Claude
    func summarizeText(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("AnthropicAPI.summarizeText called with \(text.count) characters")
        
        // Input validation
        guard !text.isEmpty else {
            print("ERROR: Empty text input")
            completion(.failure(APIError.emptyInput))
            return
        }
        
        // Get API key and initialize service if needed
        guard let apiKey = getAPIKey(), !apiKey.isEmpty else {
            print("ERROR: API key is missing or empty")
            completion(.failure(APIError.missingAPIKey))
            return
        }
        
        // Initialize Anthropic service
        if service == nil {
            service = AnthropicServiceFactory.service(apiKey: apiKey)
            print("Initialized Anthropic service with API key")
        }
        
        // Create the message content with text only
        let content: MessageParameter.Message.Content = .text(
            "This is text extracted from a screenshot using OCR. Please summarize it concisely:\n\n\(text)"
        )
        
        // Create message parameter
        let messageParam = MessageParameter.Message(role: .user, content: content)
        let parameters = MessageParameter(
            model: model,
            messages: [messageParam],
            maxTokens: maxTokens
        )
        
        // Make the API request
        print("Sending summarization request to Anthropic API...")
        Task {
            do {
                let response = try await service?.createMessage(parameters)
                
                // Extract the text content from the response
                if let content = response?.content {
                    let summary = extractTextFromContent(content)
                    print("Summarization successful: \(summary.prefix(50))...")
                    DispatchQueue.main.async {
                        completion(.success(summary))
                    }
                } else {
                    print("API ERROR: No content in response")
                    DispatchQueue.main.async {
                        completion(.failure(APIError.noData))
                    }
                }
            } catch {
                print("API ERROR: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func extractTextFromContent(_ content: [MessageResponse.Content]) -> String {
        // Join all text content from the response
        return content.compactMap { block -> String? in
            if case .text(let text) = block {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }
    
    enum APIError: Error, LocalizedError {
        case missingAPIKey
        case noData
        case invalidResponse
        case parsingError
        case emptyInput
        case httpError(Int, String)
        
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "API key is missing or empty"
            case .noData:
                return "No data received from API"
            case .invalidResponse:
                return "Invalid response format from API"
            case .parsingError:
                return "Failed to parse API response"
            case .emptyInput:
                return "Empty text input for summarization"
            case .httpError(let code, let message):
                return "HTTP error \(code): \(message)"
            }
        }
    }
}
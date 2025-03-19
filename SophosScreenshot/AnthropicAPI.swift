import Foundation
import Security
import SwiftAnthropic
import Cocoa

class AnthropicAPI {
    static let shared = AnthropicAPI()
    
    private let model = Model.claude37Sonnet
    private let maxTokens = 2048
    private var service: AnthropicService?
    
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
    
    // Function to create flashcards from OCR text using Claude
    func createFlashcards(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("AnthropicAPI.createFlashcards called with \(text.count) characters: \(text)")
        
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
            service = AnthropicServiceFactory.service(apiKey: apiKey, betaHeaders: nil)
            print("Initialized Anthropic service with API key")
        }
        
        // Get the prompt template from prompt.txt
        guard let promptTemplate = PromptTemplateLoader.loadPromptTemplate() else {
            print("ERROR: Could not load prompt template")
            completion(.failure(APIError.invalidPrompt))
            return
        }
        
        // Replace {{DESCRIPTION}} with the OCR text
        let prompt = promptTemplate.replacingOccurrences(of: "{{DESCRIPTION}}", with: text)
        
        // Create the message content with the prompt
        let content: MessageParameter.Message.Content = .text(prompt)
        
        // Create message parameter
        let messageParam = MessageParameter.Message(role: .user, content: content)
        let parameters = MessageParameter(
            model: model,
            messages: [messageParam],
            maxTokens: maxTokens
        )
        
        // Make the API request
        print("Sending flashcard creation request to Anthropic API...")
        Task {
            do {
                let response = try await service?.createMessage(parameters)
                
                // Extract the text content from the response
                if let content = response?.content {
                    let responseText = extractTextFromContent(content)
                    print("Flashcard creation successful: \(responseText.prefix(50))...")
                    print("FULL CLAUDE RESPONSE:\n\(responseText)\n")
                    
                    // Parse the flashcards from the response
                    let flashcards = extractFlashcards(from: responseText)
                    print("Extracted \(flashcards.count) flashcards from Claude response")
                    
                    // Convert flashcards to JSON
                    let flashcardsJson = convertFlashcardsToJson(flashcards)
                    print("Converted flashcards to JSON string of length \(flashcardsJson.count)")
                    
                    DispatchQueue.main.async {
                        completion(.success(flashcardsJson))
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
            if case .text(let text, _) = block {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }
    
    // Using the static method from ScreenshotManager instead
    
    // Extract flashcards from Claude's response
    private func extractFlashcards(from response: String) -> [[String: String]] {
        var flashcards: [[String: String]] = []
        
        // First, clean the response by removing any <thinking> sections
        var cleanedResponse = response
        if let thinkingRange = response.range(of: "<thinking>[\\s\\S]*?</thinking>", options: .regularExpression) {
            cleanedResponse = response.replacingCharacters(in: thinkingRange, with: "")
            print("Removed <thinking> section from Claude response")
        }
        
        // Also remove any other XML-like tags that aren't card-related
        let nonCardPatterns = ["<flashcard_creation_process>[\\s\\S]*?</flashcard_creation_process>", "<response>[\\s\\S]*?</response>"]
        for pattern in nonCardPatterns {
            if let range = cleanedResponse.range(of: pattern, options: .regularExpression) {
                cleanedResponse = cleanedResponse.replacingCharacters(in: range, with: "")
                print("Removed non-card XML section from Claude response")
            }
        }
        
        // Updated pattern to match flashcard blocks in the response, case-insensitive for tag names
        // Improved to handle more formatting variations including whitespace and newlines
        let pattern = "<card>\\s*<type_of_card>(.*?)</type_of_card>\\s*<[fF]ront>(.*?)</[fF]ront>\\s*<[bB]ack>(.*?)</[bB]ack>\\s*</card>"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let nsString = cleanedResponse as NSString
            let matches = regex.matches(in: cleanedResponse, options: [], range: NSRange(location: 0, length: nsString.length))
            
            print("Found \(matches.count) flashcard matches in Claude response")
            
            for match in matches {
                if match.numberOfRanges == 4 { // Full match + 3 capture groups
                    let typeRange = match.range(at: 1)
                    let frontRange = match.range(at: 2)
                    let backRange = match.range(at: 3)
                    
                    let type = nsString.substring(with: typeRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    let front = nsString.substring(with: frontRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    let back = nsString.substring(with: backRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let flashcard: [String: String] = [
                        "type": type,
                        "front": front,
                        "back": back
                    ]
                    
                    flashcards.append(flashcard)
                }
            }
        } catch {
            print("ERROR: Failed to parse flashcards: \(error)")
        }
        
        return flashcards
    }
    
    // Convert flashcards array to JSON string
    private func convertFlashcardsToJson(_ flashcards: [[String: String]]) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: flashcards, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            print("ERROR: Failed to convert flashcards to JSON: \(error)")
        }
        
        return "[]"
    }
    
    enum APIError: Error, LocalizedError {
        case missingAPIKey
        case noData
        case invalidResponse
        case parsingError
        case emptyInput
        case invalidPrompt
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
                return "Empty text input for flashcard creation"
            case .invalidPrompt:
                return "Could not load or process prompt template"
            case .httpError(let code, let message):
                return "HTTP error \(code): \(message)"
            }
        }
    }
}
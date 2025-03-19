import Cocoa
import Foundation
import UserNotifications
import SwiftUI
import Security
import Vision
import SwiftAnthropic
import CoreGraphics

// Define PromptTemplateLoader class for loading the prompt template
class PromptTemplateLoader {
    static func loadPromptTemplate() -> String? {
        // Get the path to prompt.txt
        guard let path = Bundle.main.path(forResource: "prompt", ofType: "txt") else {
            print("ERROR: Could not find prompt.txt in the bundle")
            return nil
        }
        
        do {
            // Read the content of the file
            let promptTemplate = try String(contentsOfFile: path, encoding: .utf8)
            return promptTemplate
        } catch {
            print("ERROR: Could not read prompt.txt: \(error)")
            return nil
        }
    }
}

class ScreenshotManager: NSObject, ObservableObject {
    private var image: NSImage?
    private var fullScreenImage: NSImage?
    private var fullScreenOCRText: String?
    // Path for saving files - use iCloud container if available, otherwise fall back to Documents directory
    private var savePath: URL {
        // Try to get the iCloud container URL
        if let iCloudContainerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
            // Create the directory if it doesn't exist
            if !FileManager.default.fileExists(atPath: iCloudContainerURL.path) {
                do {
                    try FileManager.default.createDirectory(at: iCloudContainerURL, withIntermediateDirectories: true, attributes: nil)
                    print("Created iCloud Documents directory at: \(iCloudContainerURL.path)")
                } catch {
                    print("Error creating iCloud Documents directory: \(error)")
                }
            }
            return iCloudContainerURL
        } else {
            // Fall back to local Documents directory if iCloud is not available
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
    }
    @Published var isProcessing = false
    @Published var lastDescription: String?
    
    var useDescriptionAPI: Bool {
        // Read from UserDefaults with a default of true
        return UserDefaults.standard.bool(forKey: "useDescriptionAPI")
    }
    
    var captureFullScreenContext: Bool {
        return UserDefaults.standard.bool(forKey: "captureFullScreenContext")
    }
    
    func setUseDescriptionAPI(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "useDescriptionAPI")
    }
    
    func captureScreenSelection() {
        print("Starting screenshot capture")
        // Hide the application before taking the screenshot
        NSApplication.shared.hide(nil)
        isProcessing = true
        
        // Capture full screen first if the option is enabled
        if self.useDescriptionAPI && self.captureFullScreenContext {
            self.captureFullScreen()
        }
        
        // Give some time for the app to hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Use NSTask to run the macOS screenshot utility with interactive selection
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            
            // Create a temporary file path
            let tempFilePath = NSTemporaryDirectory() + "temp_screenshot.png"
            print("Will save temp screenshot to: \(tempFilePath)")
            task.arguments = ["-i", "-s", tempFilePath]
            
            task.terminationHandler = { [weak self] process in
                guard let self = self else { return }
                print("Screenshot process terminated with status: \(process.terminationStatus)")
                
                // Create a work item for the main queue
                let workItem = DispatchWorkItem {
                    // Check if the file exists (in case user canceled)
                    if FileManager.default.fileExists(atPath: tempFilePath) {
                        print("Screenshot file exists at \(tempFilePath)")
                        if let image = NSImage(contentsOfFile: tempFilePath) {
                            self.image = image
                            print("Loaded image: \(image.size.width)x\(image.size.height)")
                            
                            // Check if we should use Vision OCR to process the image
                            if self.useDescriptionAPI {
                                print("Processing with Vision OCR")
                                self.processImageWithVisionOCR(image)
                            } else {
                                print("Saving image as JSON without text recognition")
                                self.saveImageAsJson(image)
                                self.showNotification("Screenshot captured and saved!")
                                self.isProcessing = false
                            }
                            
                            // Clean up temp file
                            try? FileManager.default.removeItem(atPath: tempFilePath)
                        } else {
                            print("Failed to load image from \(tempFilePath)")
                            self.isProcessing = false
                        }
                    } else {
                        print("Screenshot file doesn't exist - user probably canceled")
                        self.isProcessing = false
                    }
                }
                
                // Execute the work item on the main queue
                DispatchQueue.main.async(execute: workItem)
            }
            
            do {
                print("Launching screencapture command...")
                try task.run()
            } catch {
                print("Error taking screenshot: \(error)")
                self.isProcessing = false
            }
        }
    }
    
    private func captureFullScreen() {
        print("Capturing full screen for context")
        
        // Capture all screens
        if let fullScreenImage = self.takeFullScreenshot() {
            self.fullScreenImage = fullScreenImage
            
            // Process the full screen image with OCR asynchronously
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                self.processFullScreenWithVisionOCR(fullScreenImage)
            }
        }
    }
    
    private func takeFullScreenshot() -> NSImage? {
        // Use CGWindowListCreateImage to capture all screens
        guard let cgScreenImage = CGWindowListCreateImage(
            .null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution) else {
            print("Failed to create screen image")
            return nil
        }
        
        // Convert CGImage to NSImage
        let size = CGSize(width: cgScreenImage.width, height: cgScreenImage.height)
        let image = NSImage(cgImage: cgScreenImage, size: size)
        return image
    }
    
    private func processFullScreenWithVisionOCR(_ image: NSImage) {
        print("Processing full screen with Vision OCR")
        
        // Convert NSImage to CGImage for Vision processing
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to convert full screen NSImage to CGImage")
            return
        }
        
        // Create a Vision text recognition request
        let request = VNRecognizeTextRequest { [weak self] (request, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("Full screen Vision OCR error: \(error.localizedDescription)")
                return
            }
            
            // Get the text observations
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("No text observations found in full screen")
                return
            }
            
            // Extract the text from the observations
            var recognizedText = ""
            let maximumCandidates = 1  // We only want the top candidate for each observation
            
            for observation in observations {
                guard let candidate = observation.topCandidates(maximumCandidates).first else { continue }
                recognizedText += candidate.string + "\n"
            }
            
            if recognizedText.isEmpty {
                print("No text recognized in full screen")
            } else {
                print("Full screen text recognized: \(recognizedText.count) characters")
                self.fullScreenOCRText = recognizedText
            }
        }
        
        // Configure the request
        request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        request.usesLanguageCorrection = true
        
        // Create an image request handler and perform the request
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try requestHandler.perform([request])
            print("Full screen Vision request performed successfully")
        } catch {
            print("Failed to perform full screen Vision request: \(error)")
        }
    }
    
    private func processImageWithVisionOCR(_ image: NSImage) {
        // Show processing notification
        self.showNotification("Processing image with OCR...")
        print("Starting Vision OCR processing")
        
        // Convert NSImage to CGImage for Vision processing
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to convert NSImage to CGImage")
            self.saveImageAsJson(image)
            self.showNotification("Failed to process image. Saved as base64 instead.")
            self.isProcessing = false
            return
        }
        
        // Create a Vision text recognition request
        let request = VNRecognizeTextRequest { [weak self] (request, error) in
            guard let self = self else { return }
            
            // Process the results on the main queue
            DispatchQueue.main.async(execute: DispatchWorkItem {
                if let error = error {
                    print("Vision OCR error: \(error.localizedDescription)")
                    self.saveImageAsJson(image)
                    self.showNotification("OCR failed: \(error.localizedDescription)")
                    self.isProcessing = false
                    return
                }
                
                // Get the text observations
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    print("No text observations found")
                    self.saveImageAsJson(image)
                    self.showNotification("No text found in image")
                    self.isProcessing = false
                    return
                }
                
                // Extract the text from the observations
                var recognizedText = ""
                let maximumCandidates = 1  // We only want the top candidate for each observation
                
                for observation in observations {
                    guard let candidate = observation.topCandidates(maximumCandidates).first else { continue }
                    recognizedText += candidate.string + "\n"
                }
                
                if recognizedText.isEmpty {
                    print("No text recognized")
                    self.saveImageAsJson(image)
                    self.showNotification("No text recognized in image")
                    self.isProcessing = false
                } else {
                    print("Text recognized: \(recognizedText.count) characters")
                    
                    // Check if we should also summarize with Claude
                    if let savedAPIKey = UserDefaults.standard.string(forKey: "anthropic_api_key"), !savedAPIKey.isEmpty {
                        // First save the OCR text
                        self.saveOCRTextAsJson(image, recognizedText)
                        self.showNotification("Text recognized. Creating flashcards with Claude...")
                        
                        // Prepare the text to send to Claude
                        var textToProcess = recognizedText
                        
                        // If full screen context is available and enabled, include it
                        if self.captureFullScreenContext, let fullScreenText = self.fullScreenOCRText, !fullScreenText.isEmpty {
                            print("Including full screen context in Claude API request")
                            // Load the prompt template
                            if let promptTemplate = PromptTemplateLoader.loadPromptTemplate() {
                                // Check if the prompt template contains {{CONTEXT}} placeholder
                                if promptTemplate.contains("{{CONTEXT}}") {
                                    print("Found {{CONTEXT}} placeholder in prompt template")
                                    // Replace {{CONTEXT}} with the full screen OCR text
                                    textToProcess = promptTemplate.replacingOccurrences(of: "{{CONTEXT}}", with: fullScreenText)
                                    // Then replace {{DESCRIPTION}} with the interactive screenshot OCR text
                                    textToProcess = textToProcess.replacingOccurrences(of: "{{DESCRIPTION}}", with: recognizedText)
                                    print("Added full screen context (\(fullScreenText.count) chars) to Claude request")
                                } else {
                                    print("No {{CONTEXT}} placeholder found in prompt template")
                                    textToProcess = recognizedText
                                }
                            } else {
                                print("Could not load prompt template, using only screenshot text")
                                textToProcess = recognizedText
                            }
                        } else {
                            print("No full screen context available or option disabled")
                        }
                        
                        // Then send to Claude for flashcard creation
                        AnthropicAPI.shared.createFlashcards(textToProcess) { [weak self] (result: Result<String, Error>) in
                            guard let self = self else { return }
                            
                            DispatchQueue.main.async(execute: DispatchWorkItem {
                                switch result {
                                case .success(let flashcardsJson):
                                    print("SUCCESS: Claude API returned flashcards")
                                    print("Flashcards JSON length: \(flashcardsJson.count) characters")
                                    // Save both OCR text and flashcards
                                    self.saveFlashcardsAsJson(image, recognizedText, flashcardsJson)
                                    self.showNotification("Flashcards created by Claude and saved to JSON!")
                                case .failure(let error):
                                    print("Failed to create flashcards: \(error.localizedDescription)")
                                    self.showNotification("OCR text saved. Flashcard creation failed.")
                                }
                                self.isProcessing = false
                            })
                        }
                    } else {
                        // Just save the OCR results without summarization
                        self.saveOCRTextAsJson(image, recognizedText)
                        self.showNotification("Text recognized and saved!")
                        self.isProcessing = false
                    }
                }
            })
        }
        
        // Configure the request:
        // .accurate for better quality but slower processing
        // .fast for quicker results with potential lower accuracy
        request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        
        // You can also set specific languages if needed
        // request.recognitionLanguages = ["en-US", "fr-FR"]
        
        // Vision requests can be customized further:
        request.usesLanguageCorrection = true  // Apply language correction to recognized text
        
        // Create an image request handler and perform the request
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try requestHandler.perform([request])
            print("Vision request performed successfully")
        } catch {
            print("Failed to perform Vision request: \(error)")
            DispatchQueue.main.async(execute: DispatchWorkItem {
                self.saveImageAsJson(image)
                self.showNotification("OCR processing failed: \(error.localizedDescription)")
                self.isProcessing = false
            })
        }
    }
    
    private func saveImageAsJson(_ image: NSImage) {
        guard let base64String = convertImageToBase64(image) else {
            print("Failed to convert image to base64")
            return
        }
        
        // Create JSON dictionary
        let json: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "imageData": base64String
        ]
        
        saveJson(json, prefix: "screenshot_base64")
    }
    
    private func saveOCRTextAsJson(_ image: NSImage, _ recognizedText: String) {
        // Create JSON dictionary with OCR text
        let json: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "recognizedText": recognizedText,
            "imageWidth": image.size.width,
            "imageHeight": image.size.height
        ]
        
        saveJson(json, prefix: "screenshot_ocr")
    }
    
    private func saveFlashcardsAsJson(_ image: NSImage, _ originalText: String, _ flashcardsJson: String) {
        print("SAVING CLAUDE FLASHCARDS - Length: \(flashcardsJson.count) characters")
        print("Flashcards preview: \(flashcardsJson.prefix(min(100, flashcardsJson.count)))...")
        
        // Parse the flashcards JSON into an array of dictionaries if possible
        var flashcardsArray: [[String: String]] = []
        if let data = flashcardsJson.data(using: .utf8),
           let parsedArray = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            flashcardsArray = parsedArray
            print("Successfully parsed JSON into array with \(flashcardsArray.count) flashcards")
        } else {
            print("Failed to parse JSON into array, will attempt to extract flashcards directly")
            // If parsing failed, extract flashcards using regex directly in ScreenshotManager
            flashcardsArray = extractFlashcardsDirectly(from: flashcardsJson)
            print("Extracted \(flashcardsArray.count) flashcards directly from string")
        }
        
        // No longer saving a combined JSON file with the original text
        // Only save individual flashcard files
        saveIndividualFlashcards(flashcardsArray, originalText: originalText, imageSize: image.size)
    }
    
    // Save individual flashcards as separate JSON files
    private func saveIndividualFlashcards(_ flashcards: [[String: String]], originalText: String, imageSize: NSSize) {
        print("Saving \(flashcards.count) individual flashcard files...")
        
        let timestamp = Int(Date().timeIntervalSince1970)
        
        for (index, flashcard) in flashcards.enumerated() {
            // Create individual JSON for this flashcard - without the originalText
            let individualJson: [String: Any] = [
                "timestamp": timestamp,
                "cardIndex": index,
                "type": flashcard["type"] ?? "unknown",
                "front": flashcard["front"] ?? "",
                "back": flashcard["back"] ?? "",
                "imageWidth": imageSize.width,
                "imageHeight": imageSize.height
            ]
            
            // Generate filename with timestamp and index
            let filename = "flashcard_\(timestamp)_\(index).json"
            saveJsonToFile(individualJson, filename: filename)
        }
    }
    
    private func saveJsonToFile(_ json: [String: Any], filename: String) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            let fileURL = savePath.appendingPathComponent(filename)
            
            print("Saving individual JSON file to: \(fileURL.path)")
            
            try jsonData.write(to: fileURL)
            print("Successfully saved \(filename)")
        } catch {
            print("Error saving individual JSON file \(filename): \(error)")
        }
    }
    
    // Extract flashcards directly from Claude's response using regex
    private func extractFlashcardsDirectly(from response: String) -> [[String: String]] {
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
        
        // Pattern to match flashcard blocks in the response, case-insensitive for tag names
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
    
    private func saveJson(_ json: [String: Any], prefix: String) {
        print("====== SAVING JSON FILE ======")
        print("File type: \(prefix)")
        print("Keys in JSON: \(json.keys.joined(separator: ", "))")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            print("JSON serialized successfully, size: \(jsonData.count) bytes")
            
            // Generate filename with timestamp
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "\(prefix)_\(timestamp).json"
            let fileURL = savePath.appendingPathComponent(filename)
            
            print("Trying to save JSON file to: \(fileURL.path)")
            print("Save path is: \(savePath.path)")
            
            // Verify the directory exists
            if FileManager.default.fileExists(atPath: savePath.path) {
                print("Save directory exists")
            } else {
                print("WARNING: Save directory doesn't exist at \(savePath.path)")
                // Try to create it
                try FileManager.default.createDirectory(at: savePath, withIntermediateDirectories: true)
                print("Created save directory")
            }
            
            try jsonData.write(to: fileURL)
            print("SUCCESS: Data saved to: \(fileURL.path)")
            
            // Verify the file was created
            if FileManager.default.fileExists(atPath: fileURL.path) {
                print("Verified: File exists at \(fileURL.path)")
                let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64 ?? 0
                print("File size: \(fileSize) bytes")
            } else {
                print("ERROR: File was not created at \(fileURL.path)")
            }
        } catch {
            print("ERROR saving JSON: \(error)")
            print("Error details: \(error.localizedDescription)")
        }
    }
    
    func convertImageToBase64(_ image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return data.base64EncodedString()
    }
    
    private func showNotification(_ message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = "Sophos Desktop"
                content.body = message
                content.sound = UNNotificationSound.default
                
                let request = UNNotificationRequest(identifier: UUID().uuidString, 
                                                   content: content,
                                                   trigger: nil)
                
                center.add(request) { error in
                    if let error = error {
                        print("Error showing notification: \(error)")
                    }
                }
            }
        }
    }
}